# AI Config (`ai/`)

Shared AI agent configuration for **Claude Code**, **OpenCode**, and **Grok Build TUI**.

Lives in `~/.dotfiles/ai/` (skills, agents, hooks, rules, commands) and `~/.dotfiles/grok/.grok/` (native config files). The installer symlinks assets into all three tools.

## Directory Structure

```
ai/
├── agents/              # Subagent definitions (markdown + YAML frontmatter)
│   └── scout.md
├── commands/            # Shared slash commands (intentionally empty — prefer skills)
├── skills/              # Shared skills (each dir has SKILL.md + optional companions)
│   ├── agent-files/     # Authoring guide for everything under ai/
│   ├── bash/, go/, python/, rust/, …
│   ├── kubernetes/, helm/, flux/, terraform/, …
│   └── test-driven-development/, commit/, wtc/, …
├── rules/
│   └── common/          # Always-on rules (TDD, MCP routing, no-auto-commit, …)
├── hooks/               # Portable hook scripts (Grok; Claude via settings merge)
├── claude/
│   └── settings.json    # Claude hooks fragment (merged into ~/.claude/settings.json)
├── mcp-servers.json.tpl # Single MCP roster (1Password op:// secrets)
└── scripts/
    └── generate-opencode-config.sh
```

Authoring details (schemas, templates, cross-tool quirks) live in the
**`agent-files` skill** at `ai/skills/agent-files/` — not duplicated here.

## How It Works

### Claude Code

Picking `claude` from `dot install` runs `install_ai_claude()`, which:

| Source | Target |
|--------|--------|
| `ai/agents/*` | `~/.claude/agents/` |
| `ai/commands/*` | `~/.claude/commands/` |
| `ai/skills/*` | `~/.claude/skills/` |
| `ai/rules/*` | `~/.claude/rules/` |
| `ai/claude/settings.json` | deep-merged into `~/.claude/settings.json` |

Symlinks are per-item (`link_directory_contents`), so personal files in `~/.claude/` coexist alongside dotfiles-managed ones. `post_install: [generate_mcp_configs]` regenerates MCP.

### OpenCode

Picking `opencode` stows the OpenCode config package, then runs `install_ai_opencode()` + `generate_mcp_configs`:

1. Symlinks `ai/commands/*` and `ai/skills/*` into `~/.config/opencode/`
2. Runs `generate-opencode-config.sh` to convert `ai/agents/*.md` into OpenCode JSON agents and merge rules as instructions

### Grok Build TUI

Picking `grok` runs `install_ai_grok()`:

1. Symlinks `ai/skills/*`, `ai/agents/*`, and `ai/hooks/*` into native `~/.grok/`
2. Symlinks `grok/.grok/config.toml` and `grok/.grok/pager.toml` into `~/.grok/`

Grok does **not** run `generate_mcp_configs` itself. It loads MCP from `~/.claude.json` via Claude Code compatibility when that file already exists (install `claude` or `opencode` once, or run `dot mcp-regen`).

### MCP Configs

MCP servers are defined once in `ai/mcp-servers.json.tpl`. `generate_mcp_configs()` (post_install on **`claude`** and **`opencode`**, or `dot mcp-regen`) resolves 1Password secrets and writes:

- `~/.claude.json` — Claude Code + Grok compat
- `~/.config/opencode/opencode.json` — OpenCode `mcp` block

Unresolved `op://` refs are dropped when `op` is missing.

## Adding Content

> **Use the `agent-files` skill.** This document is the human-readable overview; the
> canonical authoring guide is `ai/skills/agent-files/` — `SKILL.md` plus topic
> files and templates in `examples/`. **Source of truth is always `~/.dotfiles/ai/`;
> never edit the symlinked targets.**

Quick shapes (full schemas in the skill):

**Agent** — `ai/agents/<name>.md` with frontmatter `name`, `description`, optional `model` / `tools`.

**Command** — `ai/commands/<name>.md`. Prefer a skill with `disable-model-invocation: true` for portable slash commands (this repo keeps `commands/` empty on purpose).

**Skill** — `ai/skills/<name>/SKILL.md` (+ companions as needed).

**Rule** — `ai/rules/<category>/<name>.md` (always-on instructions).

## Applying Changes

Edits under `ai/` to files that are already linked are live immediately
(tool dirs are symlinks into the repo). After adding a **new** skill/agent/
command, or to pick up repo changes on a machine:

```bash
dot update          # pull + re-link Claude/OpenCode/Grok AI + OS packages
```

`dot update` already re-runs `install_ai_claude` / `install_ai_opencode` /
`install_ai_grok` after the git pull — no separate AI install path is needed.

MCP template only: `dot mcp-regen`. Restart the agent session after adding a
skill or changing a skill *description* so catalogs reload.

## How `generate-opencode-config.sh` Works

The script bridges Claude Code's markdown agent format and OpenCode's JSON config:

1. Scans `ai/agents/*.md` and parses YAML frontmatter
2. Maps short model names to full provider IDs (e.g. `sonnet` → `anthropic/claude-sonnet-5`)
3. Converts tool lists to OpenCode's boolean format (`{read: true, bash: true}`)
4. Inlines the markdown body as the agent's prompt
5. Collects `ai/rules/**/*.md` paths as instruction references
6. Merges the generated overlay into `opencode.json` (personal config wins on conflicts)

Dependencies: `bash`, `jq`, `sed` (no Python or yq needed).
