# AI Config (`ai/`)

Shared AI agent configuration for **Claude Code**, **OpenCode**, and **Grok Build TUI**.

Lives in `~/.dotfiles/ai/` (skills, agents, hooks, rules, commands) and `~/.dotfiles/grok/.grok/` (native config files). The installer symlinks assets into all three tools.

## Directory Structure

```
ai/
├── agents/          # Claude Code agent definitions (markdown with YAML frontmatter)
├── commands/        # Shared slash commands (markdown)
├── skills/          # Shared skills (each in its own directory with SKILL.md)
│   ├── commit/
│   ├── contribute/
│   └── obsidian/
├── rules/           # Shared rules (markdown, organized by category)
│   └── common/
└── scripts/
    └── generate-opencode-config.sh   # Converts agents to OpenCode JSON format
```

## How It Works

### Claude Code

Picking `claude` from `dot install` runs `install_ai_claude()`, which symlinks each item from `ai/` into `~/.claude/`:

| Source | Target |
|--------|--------|
| `ai/agents/*` | `~/.claude/agents/` |
| `ai/commands/*` | `~/.claude/commands/` |
| `ai/skills/*` | `~/.claude/skills/` |
| `ai/rules/*` | `~/.claude/rules/` |

Symlinks are per-item (`link_directory_contents`), so personal files in `~/.claude/` coexist alongside dotfiles-managed ones.

### OpenCode

Picking `opencode` from `dot install` stows the OpenCode config and then runs `install_ai_opencode()`:

1. Symlinks `ai/commands/*` and `ai/skills/*` into `~/.config/opencode/`
2. Runs `generate-opencode-config.sh` to convert `ai/agents/*.md` into OpenCode JSON agent definitions and merge them into `opencode.json`

### Grok Build TUI

Picking `grok` from `dot install` runs `install_ai_grok()`, which does:

1. Symlinks `ai/skills/*`, `ai/agents/*`, and `ai/hooks/*` into the **native** `~/.grok/` locations (higher priority than the `~/.claude/` compatibility paths).
2. Symlinks `grok/.grok/config.toml` and `grok/.grok/pager.toml` into `~/.grok/`.

Grok also benefits automatically from:
- All MCP servers (loaded from `~/.claude.json` via its documented Claude Code compatibility layer)
- Project `AGENTS.md` / `CLAUDE.md` files (native discovery + Claude compat)

### MCP Configs

MCP servers are shared between all three platforms via `ai/mcp-servers.json.tpl`. Picking `claude`, `opencode`, or `grok` triggers `generate_mcp_configs()` which resolves 1Password secrets and writes to `~/.claude.json` (consumed by both Claude Code and Grok) and `opencode.json`.

## Adding Content

> **Use the `agent-files` skill.** This document is the human-readable overview; the
> canonical authoring guide is the skill at `ai/skills/agent-files/` — `SKILL.md` plus
> topic files (`skills.md`, `agents.md`, `commands.md`, `hooks.md`, `rules.md`,
> `mcp.md`, `workflow.md`) and templates in `examples/`. From any directory on the
> machine, an agent can invoke `/agent-files` (or be prompted with "add a skill",
> "new subagent", "add an MCP server", etc.) and it will load the right reference
> file and produce a portable artifact. **Source of truth is always `~/.dotfiles/ai/`;
> never edit the symlinked targets.**

The summaries below remain as a quick reference for humans.

### Add an Agent

Create `ai/agents/<name>.md` with YAML frontmatter:

```markdown
---
name: my-agent
description: Short description of what this agent does
model: sonnet              # opus, sonnet, haiku (or full provider ID)
tools: [read, edit, bash, grep, glob]
---

Agent prompt content goes here. This becomes the agent's system prompt
in Claude Code and the `prompt` field in OpenCode.
```

**Frontmatter reference:**

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Agent identifier (used as key in OpenCode JSON) |
| `description` | yes | One-line description |
| `model` | no | Short name (`opus`, `sonnet`, `haiku`) or full ID. Default: `sonnet` |
| `tools` | no | Comma-separated list of tools the agent can use |

Claude Code reads the markdown directly. OpenCode gets a JSON representation via `generate-opencode-config.sh`.

### Add a Command

Create `ai/commands/<name>.md`:

```markdown
---
description: What this command does
---

Command instructions here.
```

Commands appear as `/name` in both Claude Code and OpenCode.

### Add a Skill

Create `ai/skills/<name>/SKILL.md`:

```markdown
---
name: skill-name
description: What this skill provides
---

Skill content here.
```

Skills are reference material that agents and commands can invoke.

### Add Rules

Create `ai/rules/<category>/<name>.md`:

```markdown
Rule content here. These are loaded as instructions/context.
```

Rules in `ai/rules/` are symlinked into `~/.claude/rules/` for Claude Code and listed as `instructions` paths in OpenCode's config.

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

The script bridges the gap between Claude Code's markdown agent format and OpenCode's JSON config:

1. Scans `ai/agents/*.md` and parses YAML frontmatter
2. Maps short model names to full provider IDs (e.g., `sonnet` -> `anthropic/claude-sonnet-4-6`)
3. Converts tool lists to OpenCode's boolean format (`{read: true, bash: true}`)
4. Inlines the markdown body as the agent's prompt
5. Collects `ai/rules/**/*.md` paths as instruction references
6. Merges the generated overlay into `opencode.json` (personal config wins on conflicts)

Dependencies: `bash`, `jq`, `sed` (no Python or yq needed).
