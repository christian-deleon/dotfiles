# AI Config (`ai/`)

Shared AI agent configuration for **Grok Build TUI** (first-class), **OpenCode** (adapter), and **Claude Code** (adapter, opt-in).

Lives in `~/.dotfiles/ai/` (skills, agents, hooks, rules) and `~/.dotfiles/grok/.grok/` (native seed files). The installer links assets into Grok's live tree. OpenCode points at that tree.

## Directory Structure

```
ai/
├── agents/              # Subagent definitions (markdown + YAML frontmatter)
│   └── scout.md
├── skills/              # Shared skills (each dir has SKILL.md + optional companions)
├── rules/
│   └── common/          # Always-on rules (flattened into ~/.grok/rules/)
├── hooks/               # Grok hook scripts (filename prefix = event)
├── mcp-servers.json.tpl # MCP roster (1Password op:// secrets)
├── playwright-mcp.config.json
    └── scripts/
        ├── generate-opencode-config.sh   # OpenCode JSON adapter
        ├── merge-grok-mcp.py             # merge MCP + compat + base and profile overlays
        └── bedrock_grok_proxy.py         # work-machine Bedrock SSE filter
```

Authoring details live in the **`agent-files` skill** at `ai/skills/agent-files/`.

## How It Works

### Grok Build TUI (canonical)

Picking `grok` runs `install_ai_grok()` + `generate_mcp_configs`:

| Source | Target |
|--------|--------|
| `ai/skills/*` | `~/.grok/skills/` |
| `ai/agents/*` | `~/.grok/agents/` |
| `ai/hooks/*` | `~/.grok/hooks/` |
| `ai/rules/**/*.md` | `~/.grok/rules/<basename>.md` (flattened) |
| `grok/.grok/pager.toml` | `~/.grok/pager.toml` (symlink) |
| `grok/.grok/config.toml` | seed `~/.grok/config.toml` **only if missing** (live file is Grok-owned) |
| `grok/.grok/base.toml` | merged into live config on every grok install (all machines) |
| `grok/.grok/overlays/<profile>.toml` | merged after the base when `DOTFILES_PROFILE` matches (e.g. `wsl-work` Bedrock + kubernetes MCP binary); profile wins on conflict |
| `grok/.grok/trusted_folders.toml` | merged into live `~/.grok/trusted_folders.toml` |

`[compat.claude]` is forced off in the live config so leftover `~/.claude` paths are ignored. `[folder_trust] enabled = false` is forced the same way (and `GROK_FOLDER_TRUST=0` in `.commonrc`) so Grok does not block on the per-directory trust modal. Each git worktree is a separate workspace; parent grants do not cover `wtc` windows. `gra` / `tav` also pass `--trust`.

### OpenCode (adapter)

Picking `opencode` stows the OpenCode package, then `install_ai_opencode()`:

1. `~/.config/opencode/skills` → `~/.grok/skills` (one dir symlink)
2. `~/.config/opencode/AGENTS.md` → `~/.grok/AGENTS.md` when that file exists
3. `generate-opencode-config.sh` writes JSON `agent` + `instructions` (formats OpenCode cannot read from Grok) and re-applies `.provider` from `opencode.json.tpl`

Tracked template is `opencode/.config/opencode/opencode.json.tpl`. Live `opencode.json` is gitignored (MCP secrets).

| Provider | Models | Auth | Notes |
|---|---|---|---|
| `amazon-bedrock` | `deleon-*` | OpenCode `/connect` amazon-bedrock (sets `AWS_BEARER_TOKEN_BEDROCK`) | Commercial `us-east-1`. ARNs use `{env:BEDROCK_AWS_ACCOUNT_ID}` from `~/.localrc`. Omitted when that var is unset. |
| `amazon-bedrock-gov` | `work-*` | `WORK_BEDROCK_API_KEY` or `GROK_BEDROCK_API_KEY`, or `/connect` → Other → `amazon-bedrock-gov` | GovCloud OpenAI-compat endpoint. **Not** the native Bedrock SDK — a single `AWS_BEARER_TOKEN_BEDROCK` would send the personal key to GovCloud. |
| `genai-mil` | `gemini-*` (copied from the GenAI.mil model catalog) | `GENAI_MIL_API_KEY` in `~/.localrc` on the work machine, or `/connect` → Other → `genai-mil` | OpenAI-compat endpoint `https://api.genai.mil/v1`. |

Claude models on `amazon-bedrock` declare explicit `low`…`max` variants that send `thinking: {type: adaptive}` plus `output_config.effort` through `additionalModelRequestFields`, with `reasoning: false` so OpenCode's own (ARN-blind) variant logic stays off. Grok variants use `reasoningConfig` instead; Claude rejects that shape.

`dot update` / `dot install opencode` regenerates the live file.

### Claude Code (adapter, opt-in)

Not on any profile. `dot install claude` runs the native installer (`https://claude.ai/install.sh`) and `install_ai_claude()`. `dot update` refreshes the adapter only when `claude` is already on `PATH` (or `~/.local/bin/claude` exists). It does not create `~/.claude` on other machines.

`[compat.claude]` stays **off** in Grok. Claude reads its own tree. Grok does not also scan it, so the same skills are not loaded twice.

| Source | Target |
|--------|--------|
| `ai/skills/<name>/` | `~/.claude/skills/<name>` (per-directory symlink; `skills/synced/` is Claude's and is left alone) |
| `ai/agents/*.md` | `~/.claude/agents/` |
| `ai/rules/**/*.md` | `~/.claude/rules/<basename>.md` (same flatten as Grok) |
| `~/.grok/AGENTS.md` | `~/.claude/CLAUDE.md` unless the destination is a regular file |
| `ai/hooks/{stop,notification,user_prompt_submit}_*.sh` | merged into `~/.claude/settings.json` `hooks` |

`dot agent env` never touches `~/.claude/CLAUDE.md`; it relinks `~/.grok/AGENTS.md`, which the hop follows. Do not add a project `CLAUDE.md`. Current Claude Code reads a repo `AGENTS.md` on its own, and ignores it when a `CLAUDE.md` is also present in that directory or a parent.

User MCP is merged into `~/.claude.json` `mcpServers` (OAuth and UI state stay). Only the default-enabled servers (`context7`, `firecrawl`) are written. A roster server that is not enabled is omitted.

`cl` is `claude`. `cca` is `claude --permission-mode bypassPermissions`. `dot ai-tool cl` switches the interactive default. Auto-detect for commit messages stays grok, then opencode.

### MCP

Roster is `ai/mcp-servers.json.tpl`. `generate_mcp_configs()` (post_install on **`grok`**, **`opencode`**, and **`claude`**, or `dot mcp-regen`) resolves 1Password secrets and writes:

- `~/.grok/config.toml` `[mcp_servers.*]` — canonical
- `~/.config/opencode/opencode.json` `mcp` — adapter
- `~/.claude.json` `mcpServers` — adapter, only when Claude Code is installed

Unresolved `op://` refs are dropped when `op` is missing. Default-enabled: `context7`, `firecrawl`.

## Adding Content

> **Use the `agent-files` skill.** Source of truth is always `~/.dotfiles/ai/`.

**Agent** — `ai/agents/<name>.md` with frontmatter `name`, `description`, optional `model` / `tools`.

**Skill** — `ai/skills/<name>/SKILL.md`. Grok slash commands are skills.

**Rule** — `ai/rules/<category>/<name>.md` (always-on).

**Hook** — `ai/hooks/<event>_<name>.sh` (Grok filename auto-register).

## Applying Changes

Edits under `ai/` to files that are already linked are live immediately. After adding a **new** skill/agent/rule:

```bash
dot update          # pull + re-link Grok + OpenCode + Claude (if installed)
```

MCP template only: `dot mcp-regen`. Restart the agent session after adding a skill or changing a skill *description*.
