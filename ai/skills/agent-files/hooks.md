# Hooks

**Hooks** are deterministic scripts the agent runs at lifecycle moments — before a tool call, after a session starts, when the user submits a prompt, etc. They let you inject context, enforce policies, block dangerous operations, or wire the agent into external systems.

The most common AI failure mode is treating hooks as one cross-tool concept. They're not. The three tools take fundamentally different approaches:

| Tool | Hook mechanism | Stored in |
|---|---|---|
| **Claude Code** | JSON in `settings.json`, command-script handlers | `~/.claude/settings.json` or `.claude/settings.json` (dotfiles-tracked via `ai/claude/settings.json` fragment) |
| **OpenCode** | **No hooks** — TypeScript plugin modules instead | `~/.config/opencode/plugins/*.ts` |
| **Grok Build** | Codex-style TOML hook tables (also JSON `hooks.json`) | `~/.grok/hooks/` directory + inline in `~/.grok/config.toml` |

`~/.dotfiles/ai/hooks/` exists in the installer plumbing (`install_ai_grok` symlinks it into `~/.grok/hooks/`) but the directory is currently empty. **It feeds Grok only.** Claude Code hooks live in `settings.json` (not symlinked from dotfiles). OpenCode plugins live elsewhere.

### Portability — write the logic once, wrap it three times

Hooks are the one artifact type that can't be fully tool-agnostic — each tool has its own dispatch mechanism. But the **underlying logic** absolutely should be portable. Write the actual behavior as a standalone script (POSIX shell, Python, etc.) under `~/.dotfiles/ai/hooks/` or `~/.dotfiles/scripts/`, then write three thin wrappers — one Claude JSON entry, one Grok-shaped script in `ai/hooks/`, one OpenCode plugin — that each shell out to the same core script.

When you do this, the wrappers are the only tool-specific code. The logic stays in one place. See [§ Cross-tool hook strategy](#cross-tool-hook-strategy) below for the canonical pattern.

## Decision: which mechanism do you actually need?

Before writing anything, identify the goal:

| Goal | Mechanism |
|---|---|
| Block `rm -rf` or other dangerous Bash invocations | Claude `PreToolUse` hook with exit code 2; Grok `PreToolUse` hook |
| Auto-format on file save | Claude `PostToolUse` matcher `Edit|Write`; Grok `PostToolUse` |
| Inject project context at session start | Claude `SessionStart`; Grok `SessionStart`; OpenCode `session.created` event |
| Notify external system (Slack/Discord/desktop) on long-running task | Claude `Notification`; Grok `Notification`; OpenCode plugin event |
| Modify or filter tool arguments before execution | Claude `PreToolUse` with `updatedInput`; OpenCode `tool.execute.before` plugin |
| Log everything for audit | Claude any event; Grok any event; OpenCode plugin `event` handler |

If the goal needs to work in all three tools, you'll write **three implementations**. There's no portable hook format.

## Claude Code hooks

### Location

Hooks go in JSON config under the top-level `"hooks"` key:

- `~/.claude/settings.json` (user-level, all sessions)
- `.claude/settings.json` (project, checked-in)
- `.claude/settings.local.json` (project, gitignored)
- Managed (enterprise) settings

The dotfiles repo syncs Claude Code hooks via a settings fragment at `~/.dotfiles/ai/claude/settings.json`. On `dot install`, `install_ai_claude` deep-merges the fragment into `~/.claude/settings.json` — fragment keys win, but arrays per event are replaced (not concatenated), so a Stop hook in the fragment overrides any local Stop hooks.

For handler scripts of any size, drop them under `~/.dotfiles/ai/hooks/<name>.sh` and reference them by absolute path from the fragment. Keys outside the fragment (theme, effortLevel, machine-specific overrides) survive the merge untouched.

### Event types (late 2025)

`SessionStart`, `Setup`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `SessionEnd`.

### Schema

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/script.sh",
            "args": [],
            "timeout": 30,
            "if": "Bash(rm *)",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ]
  }
}
```

| Field | Notes |
|---|---|
| `matcher` | `"*"`, `""`, or omitted = all. Exact tool name (`"Bash"`), pipe-alternation (`"Edit\|Write"`), or regex (auto-detected when matcher contains non-alphanumeric chars) |
| `hooks[].type` | `command` (default), `http`, `mcp_tool`, `prompt`, `agent` |
| `hooks[].command` | Absolute path or shell command |
| `hooks[].timeout` | Seconds; default varies |
| `hooks[].if` | Permission-rule-style guard — only run when this would match |
| `hooks[].async` | Detach (don't block tool execution) |

### Stdin payload

Every hook receives JSON on stdin with at least:

```json
{
  "session_id": "01HX...",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/home/user/proj",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "effort": { "level": "medium" },
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /", "description": "wipe" },
  "tool_use_id": "toolu_..."
}
```

Event-specific extras: `prompt` (UserPromptSubmit), `file_path` and `change_type` (FileChanged), etc.

### Exit codes (command-type hooks)

| Exit | Meaning |
|---|---|
| `0` | Success, continue |
| `2` | **Block** — stderr is fed back to Claude as a tool error or guidance (only on blockable events: `PreToolUse`, `UserPromptSubmit`, `Stop`, etc.) |
| Other non-zero | Non-blocking error; logged but tool proceeds |

### Advanced JSON output

For richer control, hooks can print JSON to stdout instead of relying on exit codes:

```json
{
  "continue": true,
  "stopReason": "...",
  "suppressOutput": false,
  "systemMessage": "...",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Auto-approved git read commands",
    "updatedInput": { "command": "git diff --stat" },
    "additionalContext": "Custom context to inject",
    "applyAsPermissionRule": "Bash(git diff *)"
  }
}
```

`PostToolUse`/`Stop`/`SubagentStop`/`PreCompact` use `{ "decision": "block", "reason": "..." }` instead. `SessionStart` injects via `hookSpecificOutput.additionalContext`.

### Minimal example

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "test \"$(jq -r .tool_input.command)\" != 'rm -rf /'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

A real hook would normally `exec` a script in `~/.dotfiles/ai/hooks/<name>.sh` — see [`examples/hook.template.json`](examples/hook.template.json).

## Grok Build hooks

### Location

- `~/.grok/hooks/` — directory of hook scripts (dotfiles-managed via `ai/hooks/`)
- `.grok/hooks/` — project hooks (requires `/hooks-trust` approval first run)
- `~/.grok/config.toml` — inline hook tables (Codex style, partly inferred)
- Plugins ship hooks too

This repo's installer already symlinks `~/.dotfiles/ai/hooks/*` → `~/.grok/hooks/`. So **dropping a script into `ai/hooks/` is the canonical path for Grok hooks**.

### TOML inline syntax (Codex-style)

```toml
[[hooks.PreToolUse]]
matcher = "^Bash$"

[[hooks.PreToolUse.hooks]]
type          = "command"
command       = '/usr/bin/python3 ~/.grok/hooks/pre_tool_use.py'
timeout       = 30
statusMessage = "Checking Bash command"
```

Inline TOML in `config.toml` and a separate `hooks.json` file both work. The script-on-disk form (a file in `~/.grok/hooks/`) is auto-discovered by name — `pre_tool_use.sh` registers as a `PreToolUse` hook automatically.

### Event types (reported, partly inferred)

`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `UserPromptSubmit`, `SessionStart`, `SessionEnd`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `PreCompact`, `PostCompact`, `Notification`, `InstructionsLoaded`, `CwdChanged`. Mirrors Claude's set closely.

### Stdin / exit codes

Stdin is JSON (same general shape as Claude). Exit codes: `0` ok, `2` block, other non-zero = non-blocking error. Same conventions as Claude — write hook scripts to be portable between the two.

### Authoring guidance

Drop the script in `~/.dotfiles/ai/hooks/` with a name that encodes the event:

```
ai/hooks/
├── pre_tool_use_bash_safety.sh    # auto-registers as PreToolUse for Bash
├── session_start_inject_context.sh
└── post_tool_use_format_on_save.sh
```

After `dot install`, they appear at `~/.grok/hooks/`. Verify with `grok inspect` (which lists which hooks are active and from which source).

## OpenCode "hooks" — they're plugins

OpenCode has no hook system in the Claude/Grok sense. Instead, it has a **plugin** system: TypeScript modules that subscribe to events.

### Location

```
.opencode/plugins/<name>.ts        # project
~/.config/opencode/plugins/<name>.ts  # user
```

Or installed via `plugin: ["my-pkg"]` in `opencode.json`.

### Plugin shape

```typescript
import type { Plugin } from "@opencode-ai/plugin";

export const SafetyPlugin: Plugin = async ({ project, client, $, directory, worktree }) => ({
  "tool.execute.before": async (input, output) => {
    if (input.tool === "bash" && input.args.command?.includes("rm -rf /")) {
      throw new Error("Blocked: rm -rf /");
    }
  },
  "tool.execute.after": async (input, output) => {
    // observe results, log, etc.
  },
  event: async ({ event }) => {
    // generic event-bus handler
  },
});
```

### Events

`tool.execute.before`, `tool.execute.after`, `session.created`, `session.updated`, `session.compacted`, `session.idle`, `message.updated`, `message.removed`, `message.part.updated`, `command.executed`, `shell.env`, `file.edited`, `file.watcher.updated`, `lsp.updated`, `lsp.client.diagnostics`, `tui.prompt.append`, `tui.command.execute`, `server.connected`, `permission.asked`, `installation.updated`, `todo.updated`.

This repo does **not** currently sync OpenCode plugins from dotfiles. If you want one, drop it in `~/.config/opencode/plugins/` manually, or add a new install step.

## Cross-tool hook strategy

If you need the same behavior in all three tools:

1. Write the **logic** as a standalone script under `~/.dotfiles/scripts/` or `~/.dotfiles/ai/hooks/` (POSIX shell or Python — something portable).
2. For **Claude**: reference the script by absolute path from the `~/.dotfiles/ai/claude/settings.json` fragment (merged into `~/.claude/settings.json` on `dot install`).
3. For **Grok**: drop the script (or a symlink to it) in `~/.dotfiles/ai/hooks/` with an event-prefixed filename.
4. For **OpenCode**: write a thin TypeScript plugin that shells out to the same script via `$`.

This is the only way to keep one source of truth for the logic; the wrappers are tool-specific.

## Stdin payload — what hooks can rely on

Across Claude and Grok, hooks reliably get on stdin:

```json
{
  "session_id": "string",
  "cwd": "string",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { ... }
}
```

Anything beyond that is event- and tool-specific. Defensive parsing: treat fields as optional, default to safe behavior.

## Minimal canonical example

See [`examples/hook.template.json`](examples/hook.template.json) for the Claude JSON shape and [`examples/hook.template.toml`](examples/hook.template.toml) for the Grok inline TOML shape. A shell-script handler that works in both:

```bash
#!/usr/bin/env bash
# ai/hooks/pre_tool_use_bash_safety.sh
# Block dangerous Bash invocations. Exit 2 = block, 0 = allow.
set -Eeuo pipefail

payload="$(cat)"
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"

case "$cmd" in
  *"rm -rf /"*|*"rm -rf ~"*|*":(){:|:&};:"*)
    echo "Blocked: dangerous Bash invocation" >&2
    exit 2
    ;;
esac
exit 0
```

## After authoring

1. **Claude Code hooks**: edit `~/.dotfiles/ai/claude/settings.json` and run `dot install` to merge into `~/.claude/settings.json`. Restart Claude Code so it re-reads settings.
2. **Grok hooks**: `dot install` symlinks them in. Verify with `grok inspect`.
3. **OpenCode plugins**: tell the user to drop the `.ts` file in `~/.config/opencode/plugins/` and restart OpenCode.
