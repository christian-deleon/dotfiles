# AI Config (`ai/`)

Shared AI agent configuration for **Grok Build TUI** (first-class) and **OpenCode** (adapter).

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
        ├── merge-grok-mcp.py             # merge MCP + compat + profile overlay
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
| `grok/.grok/overlays/<profile>.toml` | merged into live config when `DOTFILES_PROFILE` matches (e.g. `wsl-work` Bedrock + kubernetes MCP binary) |
| `grok/.grok/trusted_folders.toml` | merged into live `~/.grok/trusted_folders.toml` |

`[compat.claude]` is forced off in the live config so leftover `~/.claude` paths are ignored.

### OpenCode (adapter)

Picking `opencode` stows the OpenCode package, then `install_ai_opencode()`:

1. `~/.config/opencode/skills` → `~/.grok/skills` (one dir symlink)
2. `~/.config/opencode/AGENTS.md` → `~/.grok/AGENTS.md` when that file exists
3. `generate-opencode-config.sh` writes JSON `agent` + `instructions` (formats OpenCode cannot read from Grok)

### MCP

Roster is `ai/mcp-servers.json.tpl`. `generate_mcp_configs()` (post_install on **`grok`** and **`opencode`**, or `dot mcp-regen`) resolves 1Password secrets and writes:

- `~/.grok/config.toml` `[mcp_servers.*]` — canonical
- `~/.config/opencode/opencode.json` `mcp` — adapter

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
dot update          # pull + re-link Grok + OpenCode adapter
```

MCP template only: `dot mcp-regen`. Restart the agent session after adding a skill or changing a skill *description*.
