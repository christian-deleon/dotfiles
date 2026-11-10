# Hooks

**Hooks** are deterministic scripts the agent runs at lifecycle moments — before a tool call, after a session starts, when the user submits a prompt, etc. They let you inject context, enforce policies, block dangerous operations, or wire the agent into external systems.

The most common AI failure mode is treating hooks as one cross-harness concept. The scripts are shared; registration is per harness.

| Harness | Hook mechanism | This repo |
|---|---|---|
| **Grok Build** | Filename auto-register, JSON `hooks.json`, or TOML in `config.toml` | `install_ai_grok` links `ai/hooks/*` → `~/.grok/hooks/`; the event-prefixed filename registers it |
| **OpenCode** | **No hooks** — TypeScript plugins | `opencode/.config/opencode/plugins/notify-sound/tui.js` calls `stop_notify.sh` |
| **Claude Code** | `hooks` in `~/.claude/settings.json` | `ensure_claude_settings` merges `stop_notify.sh`, `notification_notify.sh`, `user_prompt_submit_clear.sh` |

Scripts live once in `ai/hooks/` (`stop_notify.sh`, `notification_notify.sh`, `user_prompt_submit_clear.sh`, `notify_common.sh`). **Adding a hook means registering it for each harness that should run it** — a new file in `ai/hooks/` reaches Grok automatically, Claude only after it's added to `ensure_claude_settings`, OpenCode only through a plugin.

Grok's payload is camelCase and Claude's is snake_case. A script shared by both must read only fields spelled the same in both (e.g. `cwd`), or read both spellings.

## Decision: which mechanism?

| Goal | Mechanism |
|---|---|
| Block `rm -rf` or other dangerous Bash | Grok `PreToolUse` (matcher `Bash` or `run_terminal_command`), exit 2 or `{"decision":"deny"}` |
| Auto-format on file save | Grok `PostToolUse` matcher `Edit\|Write` (aliases to `search_replace`) |
| Inject project context at session start | Grok `SessionStart` |
| Notify on idle / permission wait | Grok `Notification` — use matcher `idle_prompt` or `permission_prompt` (Grok also fires Notification on every turn-end; see existing `notification_notify.sh`) |
| Keep the agent working until tests pass | Grok `Stop` / `SubagentStop` gate — `{"decision":"block","reason":"…"}` or exit 2 |
| Same behavior in Claude Code | Same script, registered in `ensure_claude_settings` (snake_case payload) |
| Same behavior in OpenCode | Not hooks. A TypeScript plugin under `opencode/.config/opencode/plugins/` that shells out to the script |

## Grok hook locations

| Scope | Path | Trusted? |
|---|---|---|
| Global scripts (this repo) | `~/.grok/hooks/*` via `ai/hooks/` | Always |
| Global JSON | `~/.grok/hooks/*.json` | Always |
| Config TOML | `~/.grok/config.toml` `[[hooks.<Event>]]` | Always |
| Project | `<project>/.grok/hooks/` | Requires folder trust (`/hooks-trust`) |
| Compat (off in this repo) | leftover `~/.claude/settings.json`, `~/.cursor/hooks.json` | `[compat.claude] hooks = false` |

Project hooks are silent until the folder is trusted. `--trust` / `/hooks-trust` grants MCP, LSP, **and** hooks together.

## Grok filename auto-register

```
ai/hooks/
├── pre_tool_use_bash_safety.sh    # PreToolUse
├── stop_notify.sh                 # Stop
├── notification_notify.sh         # Notification
└── user_prompt_submit_clear.sh    # UserPromptSubmit
```

After `dot update` (or `dot install grok`), they appear at `~/.grok/hooks/`. Verify with `grok inspect` and the `/hooks` modal.

## Events

Official Grok events:

| Event | When | Blocking? |
|---|---|---|
| `SessionStart` | Session starts | No |
| `UserPromptSubmit` | User submits a prompt | No |
| `PreToolUse` | Tool about to run | Yes — can deny |
| `PostToolUse` | Tool succeeds | No |
| `PostToolUseFailure` | Tool fails | No |
| `PermissionDenied` | Permission system denies a call | No |
| `Stop` | Turn ends on a genuine completion | Yes — can block the stop |
| `StopFailure` | Turn ends on an API error | No (observe only) |
| `Notification` | User-attention (`idle_prompt`, `permission_prompt`, `task_complete`, …) | No |
| `SubagentStart` | Subagent starts | No |
| `SubagentStop` | Subagent turn ends | Yes — can block the stop |
| `PreCompact` / `PostCompact` | Compaction | No |
| `SessionEnd` | Session ends | No |

`SubagentEnd` is accepted as an alias for `SubagentStop`. Matcher on `Stop` or `UserPromptSubmit` is ignored.

## Matcher and tool-name aliases

`matcher` is a regex. What it tests depends on the event: tool name on tool events, notification type on `Notification`, subagent type on `SubagentStart`/`SubagentStop`, etc. Empty / omitted = all.

Grok maps Claude-shaped names so migrated matchers still fire:

| Matcher | Also matches |
|---|---|
| `Bash` | `run_terminal_command` |
| `Read` | `read_file` |
| `Edit`, `Write`, `MultiEdit` | `search_replace` |
| `Grep` | `grep` |
| `Glob`, `ListDir` | `list_dir` |
| `WebSearch` | `web_search` |
| `Task` | `spawn_subagent` |

A matcher keeps its original name too, so `Bash` matches both. MCP tools appear as `server__tool` (e.g. `linear__save_issue`), not the dispatcher name.

For finish-thinking chimes, matcher `idle_prompt` on `Notification`. `permission_prompt` fires only when a permission UI is waiting. This repo's `notification_notify.sh` exits immediately under Grok because Grok also fires Notification on every turn-end (double-toast with Stop).

## Stdin (camelCase)

Grok's envelope is **camelCase**, not Claude snake_case. A script reading `.tool_input` or `.hook_event_name` will miss the fields.

```json
{
  "hookEventName": "pre_tool_use",
  "sessionId": "abc-123",
  "cwd": "/home/you/project",
  "workspaceRoot": "/home/you/project",
  "permissionMode": "default",
  "toolName": "run_terminal_command",
  "toolInput": { "command": "npm test" },
  "timestamp": "2026-04-14T12:00:00Z"
}
```

Common fields on every event: `hookEventName`, `sessionId`, `cwd`, `workspaceRoot`, `timestamp`, `permissionMode` (`default`, `auto`, `plan`, `bypassPermissions`). Tool events add `toolName`, `toolInput`, `toolUseId`. `PostToolUse` output is `toolResult` (not `tool_response`).

Defensive parsing: treat extra fields as optional. The shared notify hooks read only `.cwd`, which both harnesses spell the same.

Env always injected: `GROK_HOOK_EVENT`, `GROK_HOOK_NAME`, `GROK_SESSION_ID`, `GROK_WORKSPACE_ROOT`. `CLAUDE_PROJECT_DIR` is also set (alias for workspace root) — don't build new hooks around the Claude name.

## Exit codes and JSON decisions

| Exit | Meaning |
|---|---|
| `0` | Success / allow |
| `2` | Explicit deny (`PreToolUse`) or block-stop (`Stop` / `SubagentStop`); stderr is feedback when stdout has no JSON |
| Other | Fail-open — recorded but nothing is blocked |

**PreToolUse** — write JSON to stdout:

- Allow: `{"decision": "allow"}`
- Deny: `{"decision": "deny", "reason": "Unsafe command detected"}`

A `deny` decision in stdout is honored regardless of exit code.

**Stop / SubagentStop** — keep the agent working:

- `{"decision": "block", "reason": "The test suite hasn't been run yet"}` — reason fed back, another round
- `{"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": "…"}}` — also keeps working, softer
- `{"continue": false, "stopReason": "Budget exhausted"}` — force stop
- Exit 0 / no JSON — allow the stop
- Exit 2 — block, stderr as feedback

Cap: **8 continuations** per turn, then the gate is overridden. Check `stopHookActive` so you don't loop on a condition that will never resolve. Filter `reason == "end_turn"` — an extra observe-only Stop fires at session end (`channel_closed` / `shutdown`). Interrupted (Esc) turns skip Stop entirely; API errors fire `StopFailure` (observe only).

Default timeout: **5s**, or **600s** for `Stop`/`SubagentStop`. Set `timeout` explicitly when a gate runs tests.

## TOML / JSON (optional)

Prefer a script in `ai/hooks/`. If you need inline config:

```toml
[[hooks.PreToolUse]]
matcher = "Bash|Write|Edit"
hooks = [
  { type = "command", command = "/home/you/.dotfiles/ai/hooks/pre_tool_use_bash_safety.sh", timeout = 10 },
]
```

JSON files under `~/.grok/hooks/*.json` use the same object Grok documents (event → matcher groups → handlers). See [`examples/hook.template.toml`](examples/hook.template.toml).

## Minimal script

```bash
#!/usr/bin/env bash
# ai/hooks/pre_tool_use_bash_safety.sh
# Block dangerous Bash. Exit 2 = deny; prefer JSON deny on stdout.
set -Eeuo pipefail

payload="$(cat)"
cmd="$(jq -r '.toolInput.command // .tool_input.command // ""' <<<"$payload")"

case "$cmd" in
  *"rm -rf /"*|*"rm -rf ~"*|*":(){:|:&};:"*)
    printf '%s\n' '{"decision":"deny","reason":"Blocked potentially destructive command"}'
    exit 2
    ;;
esac
printf '%s\n' '{"decision":"allow"}'
```

Read **both** camelCase and snake_case when the script runs under Grok and Claude.

## Claude Code registration

`ensure_claude_settings` (run by `install_ai_claude`) merges three command hooks into `~/.claude/settings.json`: `Stop` → `stop_notify.sh`, `Notification` (matcher `permission_prompt|elicitation_dialog`) → `notification_notify.sh`, `UserPromptSubmit` → `user_prompt_submit_clear.sh`. The command path is the script in `ai/hooks/`. The matcher skips `idle_prompt`, which would repeat the Stop toast about a minute after each turn. Re-running the installer replaces a stale entry for the same `command` instead of adding a second one. To register another script for Claude, add an `ensure_hook` line there. `notification_notify.sh` exits immediately when the parent process is Grok, because Grok also fires Notification on every turn end.

## OpenCode — plugins, not hooks

OpenCode has no hook system. TypeScript plugins subscribe to `tool.execute.before`, `session.created`, etc. Plugins live in the stowed `opencode/.config/opencode/plugins/`; `notify-sound/tui.js` calls `stop_notify.sh`. For another shared behavior, write a plugin that shells out to the `ai/hooks/` script.

## After authoring

1. `bash -n` (and `shellcheck` if installed) the script.
2. Register it for each harness that should run it (see table above), then `dot update`.
3. `grok inspect` and `/hooks` (Grok), `/hooks` (Claude) to confirm it loaded.
4. Trigger the event.
