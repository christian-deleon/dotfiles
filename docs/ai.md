# AI Config (`ai/`)

Shared AI agent configuration for three peer harnesses: **Claude Code**, **Grok Build**, and **OpenCode**. One source in `~/.dotfiles/ai/` (skills, agents, rules, hooks, MCP roster); each harness has its own installer that links or generates from it into the harness's own tree. No harness reads another's files.

## Directory Structure

```
ai/
├── agents/              # Subagent definitions (markdown + YAML frontmatter)
├── models.yaml          # Model and effort per job, per harness
├── skills/              # Shared skills (each dir has SKILL.md + optional companions)
├── rules/
│   └── common/          # Always-on rules (flattened per harness)
├── hooks/               # Hook scripts shared by the harnesses, plus Grok's dotfiles.json
├── mcp-servers.json.tpl # MCP roster (1Password op:// secrets)
├── playwright-mcp.config.json
└── scripts/
    ├── generate-opencode-config.sh   # OpenCode agents + instructions JSON
    ├── merge-grok-mcp.py             # Grok config.toml merge (MCP, compat, overlays)
    └── bedrock_grok_proxy.py         # work-machine Bedrock SSE filter
```

Authoring details live in the **`agent-files` skill** at `ai/skills/agent-files/`.

## Which harnesses a machine gets

Harnesses are manifest items (`claude`, `grok`, `opencode`). With an active profile, the profile's `items:` decide: only listed harnesses are configured, refreshed on `dot update`, and fed MCP, and `dot install <harness>` refuses one the profile leaves out. Without a profile, whatever is installed is configured. The registry (`AI_HARNESSES`, `ai_harness_enabled`) lives in `scripts/lib.sh`.

| Profile | Harnesses | `ai.default` |
|---|---|---|
| omarchy-personal, wsl-personal, macos-personal | claude, grok, opencode | claude |
| wsl-work | grok, opencode (Claude Code is not allowed there) | opencode |

`ai.default` is written to `~/.localrc` as `AI_TOOL` / `AI_TOOL_RESUME` / `AI_TOOL_PIPE` (used by `tav`, `wta`, `wtc`, and commit-message generation) only when `~/.localrc` has no `AI_TOOL` yet. `dot ai-tool [INT] [PIPE]` overrides it; its picker lists only enabled harnesses. With `AI_TOOL_PIPE` unset, commit-message generation auto-detects claude > opencode > grok.

## Per harness

### Claude Code

`dot install claude` runs the native installer (`https://claude.ai/install.sh`) and `install_ai_claude()`:

| Source | Target |
|--------|--------|
| `ai/skills/<name>/` | `~/.claude/skills/<name>` (per-directory symlink; `skills/synced/` is Claude's and is left alone) |
| `ai/agents/*.md` | `~/.claude/agents/` (symlink, or a rendered file for an agent with a `job:`) |
| `ai/rules/**/*.md` | `~/.claude/rules/<basename>.md` (flattened) |
| `ai/hooks/*.sh` (notify toasts, `session_state.sh`) | merged into `~/.claude/settings.json` `hooks`, plus blank commit/PR attribution |

Do not add a project `CLAUDE.md`. Claude Code reads a repo `AGENTS.md` on its own, and ignores it when a `CLAUDE.md` is also present in that directory or a parent.

`cl` is `claude`. `cca` is `claude --permission-mode bypassPermissions`.

### Grok Build

`install_ai_grok()`:

| Source | Target |
|--------|--------|
| `ai/skills/*` | `~/.grok/skills/` |
| `ai/agents/*.md` | `~/.grok/agents/` (symlink, or a rendered file for an agent with a `job:`) |
| `ai/hooks/*` | `~/.grok/hooks/` (`dotfiles.json` registers the scripts; Grok reads only `*.json` there) |
| `ai/rules/**/*.md` | `~/.grok/rules/<basename>.md` (flattened) |
| `grok/.grok/pager.toml` | `~/.grok/pager.toml` (symlink) |
| `grok/.grok/config.toml` | seed `~/.grok/config.toml` **only if missing** (Grok mutates the live file) |
| `grok/.grok/base.toml` | merged into the live config on every install |
| `grok/.grok/overlays/<profile>.toml` | Grok-only settings merged after the base (e.g. `wsl-work` GovCloud Bedrock models); profile wins on conflict. MCP tables here are ignored — MCP comes from the profile. |
| `grok/.grok/trusted_folders.toml` | merged into live `~/.grok/trusted_folders.toml` |

`[compat.claude]` is forced off: the Claude installer fills `~/.claude` from the same sources, so Grok scanning it would load everything twice. `[folder_trust] enabled = false` is forced the same way (and `GROK_FOLDER_TRUST=0` in `.commonrc`) so Grok does not block on the per-directory trust modal. Each git worktree is a separate workspace; parent grants do not cover `wtc` windows. `gra` / `tav` also pass `--trust`.

### OpenCode

Picking `opencode` stows the OpenCode package, then `install_ai_opencode()` (skipped until `~/.config/opencode` is stowed):

1. `ai/skills/<name>/` → `~/.config/opencode/skills/<name>` (per-directory symlinks in the stowed package's gitignored `skills/`)
2. `generate-opencode-config.sh` writes `agent` (from `ai/agents/*.md`, with each job agent's model and variant) and `instructions` (paths of `ai/rules/**/*.md`) into `opencode.json`, and re-applies `.provider` and `.plugins` from `opencode.json.tpl`

OpenCode also reads `~/.claude/skills` natively. Same-named skills resolve by precedence to the same files, so the overlap is harmless.

Tracked template is `opencode/.config/opencode/opencode.json.tpl`. Live `opencode.json` is gitignored (MCP secrets). Agent/provider keys still use the 1.x names OpenCode 2 accepts; MCP is written in the 2.0 shape (`mcp.servers`). 1.x-only fields such as `whitelist` and model `reasoning` are ignored by 2.0, so don't add them.

Other tracked OpenCode 2 files:

| File | Role |
|---|---|
| `cli.json` | TUI settings (theme, diff view, sidebar). Replaced `tui.json` in 2.0; the TUI writes to it from Ctrl+P → Open settings. |
| `plugins/model-allowlist/index.js` | 2.0 config has no per-provider model allow-list. The template's `plugins` entry passes provider ID → model IDs to keep (the three `deleon-*` Bedrock profiles); this server plugin hides the rest of that provider's catalog. |
| `plugins/notify-sound/tui.js` | Runs `ai/hooks/stop_notify.sh` when a root session this TUI shows goes idle. OpenCode has plugins, not hooks; a TUI plugin because the 2.0 server is one shared background process with the wrong `TMUX_PANE`. |

On Omarchy the binary comes from its `~/.local/bin/opencode` mise wrapper. 2.0 is not on the aqua/GitHub-releases backend Omarchy uses, so switch the wrapper with `omarchy-mise-install npm:@opencode/cli opencode`, then set `"npm:@opencode/cli" = { version = "latest", allow_builds = ["@opencode/cli"] }` in `~/.config/mise/config.toml` (its postinstall fetches the native binary) and `mise unuse --no-prune -g opencode`.

| Provider | Models | Auth | Notes |
|---|---|---|---|
| `amazon-bedrock` | `deleon-*` | OpenCode `/connect` amazon-bedrock (sets `AWS_BEARER_TOKEN_BEDROCK`) | Commercial `us-east-1`. ARNs use `{env:BEDROCK_AWS_ACCOUNT_ID}` from `~/.localrc`. Omitted when that var is unset. |
| `amazon-bedrock-gov` | `work-*` | `WORK_BEDROCK_API_KEY` or `GROK_BEDROCK_API_KEY`, or `/connect` → Other → `amazon-bedrock-gov` | GovCloud OpenAI-compat endpoint. **Not** the native Bedrock SDK — a single `AWS_BEARER_TOKEN_BEDROCK` would send the personal key to GovCloud. |
| `genai-mil` | `gemini-*` (copied from the GenAI.mil model catalog) | `GENAI_MIL_API_KEY` in `~/.localrc` on the work machine, or `/connect` → Other → `genai-mil` | OpenAI-compat endpoint `https://api.genai.mil/v1`. |

Claude models on `amazon-bedrock` declare explicit `low`…`max` variants that send `thinking: {type: adaptive}` plus `output_config.effort` through `additionalModelRequestFields`. The ARN models are not in OpenCode's catalog, so only the declared variants exist. Grok variants use `reasoningConfig` instead; Claude rejects that shape.

`dot update` / `dot install opencode` regenerates the live file. The 2.0 background service cannot watch `~/.config/opencode` because it is a stow symlink, so the installer runs `opencode reload` after regenerating.

## Models per job

`ai/models.yaml` names a model and effort for each job (`plan`, `implement`, `review`, `small`), once per harness. Nothing else in `ai/` names a model:

- An agent sets `job: <name>` in its frontmatter. The Claude and Grok installers render it into a real file with that job's `model` and `effort` instead of a symlink; the OpenCode generator sets `model` and `variant` (the effort, which must be a variant the provider declares). A job with no entry for a harness leaves the agent on the session's model.
- `wto new -j <job>` starts a session on the job's model for the harness in `$AI_TOOL`; `-m` / `-e` override it. OpenCode takes no per-session model.
- Skills name jobs (`wtc` picks one per task).

A profile's `models:` block replaces single job + harness entries for that machine (`wsl-work` puts every job on GovCloud Grok 4.7). The installer writes the merged table to `~/.local/state/dotfiles/ai-models.json`, which `wto` reads. After editing either file, run `dot update`: rendered agents do not follow edits to `ai/agents/` until then.

The planner, implementer and reviewer agents carry the plan, implement and review jobs; the `plan-implement-review` skill runs them.

## Per-env instructions

`dot agent env link <name>` links `agent-files/env/<name>/AGENTS.md` straight into each enabled harness's user instructions file (`~/.claude/CLAUDE.md`, `~/.grok/AGENTS.md`, `~/.config/opencode/AGENTS.md`) and env skills into each skills dir. See [dot-agent.md](dot-agent.md).

## Orchestrating worktree sessions

One agent session per worktree, each in its own tmux window (`wtc`, `wta`, `wtaa`), with the main worktree as home base. These pieces let the main session coordinate the others:

| Piece | Role |
|---|---|
| `bin/wto` | Roster (`ls`), messages with an origin header (`send`, `header`), shared-resource claims (`claim`), closing merged sessions (`close`), the orchestrator marker (`here`). See [functions.md](functions.md#wto-command). |
| `ai/hooks/session_state.sh` | Records working / idle / blocked / exited on the AI pane, so `wto send` never types into a question or a dead pane. |
| `ai/rules/common/session-messages.md` | How every session tells a peer message from the user. |
| `/orchestrate` | Run in the main worktree: status, broadcasts, pause and resume, rebase notices, dispatching work (with a model and effort per session), claims, close-outs. Never does task work. Fixes the project's own orchestration setup when it proves wrong; suggests changes to the skills and tools instead of making them. |
| `/spinoff` | Run in a feature session: file unrelated work as an issue and hand the number to main. |
| `/closeout` | Run in a feature session when done: merge (if the project allows), free claims, ask main to close the window. |
| `/backlog` | Run in the orchestrator: pick a capped batch of issues that can run side by side. |
| `/onboard` | Run once per project: write its project profile. |
| `orchestrated-session` | Loaded by a feature session when an orchestrator runs: test, check and review its own work, report with one fixed status report, and deploy or merge only on the owner's go relayed by the orchestrator. Not a slash command. |

Messages use the harness's own session messaging where the receiver has it (Claude Code between Claude sessions; the OpenCode server for OpenCode) and a bracketed paste into the tmux pane otherwise (Grok). State that must survive restarts lives in `<git-common-dir>/orchestrate/`, which every worktree shares and git never tracks.

**Project profile.** Project specifics never go into `ai/`. `/onboard` writes the project profile to its own file, `.agents/profile.md` in the repo, or `profile.md` beside a `dot agent` overlay's `AGENTS.md`, so sessions load it only when a skill needs it (`wto profile` prints it). It records kind (personal, work, public), issue-draft review, merge policy, tracker and priority, session cap, model default and limits, shared resources, main-only and work-producing skills, branch naming, and instructions for the named orchestration moments (`ai/skills/orchestrate/moments.md`). `/issue`, `/closeout`, `/orchestrate` and `/backlog` read it; without one they use cautious defaults (drafts reviewed, merges asked, cap 5).

## MCP

Roster is `ai/mcp-servers.json.tpl`. The active profile's `mcp:` block is the only source of truth for what is on:

```yaml
mcp:
  enable: [context7, firecrawl, kubernetes]
  override:
    kubernetes:
      command: kubernetes-mcp-server   # command without args drops the roster args
```

Without a profile (or a profile without `mcp:`), the roster entries marked `"default": true` (context7, firecrawl) are on. `generate_mcp_configs()` (post_install on each harness item, or `dot mcp-regen`) applies the overrides, resolves 1Password secrets for the enabled servers only, and writes exactly that set to every enabled harness:

- `~/.claude.json` `mcpServers` (roster servers not enabled are removed; servers you added by hand stay)
- `~/.grok/config.toml` `[mcp_servers.*]` (enabled names are also taken out of `[tools] disabled_mcp_servers`)
- `~/.config/opencode/opencode.json` `mcp.servers`

A server switched on in a harness's own UI is reset on the next regen. Regen is skipped while the roster, the profile's `mcp:` block, and the harness list are unchanged and every harness still has what it was last given; `dot mcp-regen` forces it. Unresolved `op://` refs are dropped when `op` is missing.

The `gitea` entry reads host and token from one 1Password item and is for the personal Netbird-only Gitea; see `ai/rules/common/gitea.md`. `tea` logs in from the same item (`install_tea_login`, `dot install tea`). `wsl-work` runs the local `kubernetes-mcp-server` binary because npm/`npx` is blocked there.

## Adding Content

> **Use the `agent-files` skill.** Source of truth is always `~/.dotfiles/ai/`.

**Agent** — `ai/agents/<name>.md` with frontmatter `name`, `description`, optional `job` / `tools` / `disallowedTools`. Pin a model through `job:`, not `model:`.

**Skill** — `ai/skills/<name>/SKILL.md`. Slash commands are skills in all three harnesses.

**Rule** — `ai/rules/<category>/<name>.md` (always-on). Basenames must be unique: rules are flattened.

**Hook** — `ai/hooks/<event>_<name>.sh`. Grok needs an entry in `ai/hooks/dotfiles.json`; Claude needs an entry in `ensure_claude_settings`; OpenCode needs a plugin.

## Applying Changes

Edits under `ai/` to files that are already linked are live immediately. After adding a **new** skill/agent/rule:

```bash
dot update          # pull + re-link every enabled harness
```

MCP roster or profile `mcp:` change: `dot mcp-regen`. Restart the agent session after adding a skill or changing a skill *description*.
