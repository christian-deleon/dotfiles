# AI Config (`ai/`)

Shared AI agent configuration for Claude Code and OpenCode. Lives in `~/.dotfiles/ai/` and is symlinked into both platforms by the installer.

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

### MCP Configs

MCP servers are shared between both platforms via `ai/mcp-servers.json.tpl`. Picking either `claude` or `opencode` triggers `generate_mcp_configs()` which resolves 1Password secrets and writes to both `~/.claude.json` and `opencode.json`.

## Adding Content

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

After adding or modifying files in `ai/`:

```bash
dot update          # Re-installs AI config for both platforms
# or
dot install         # Pick 'claude' and/or 'opencode' from the picker
```

## How `generate-opencode-config.sh` Works

The script bridges the gap between Claude Code's markdown agent format and OpenCode's JSON config:

1. Scans `ai/agents/*.md` and parses YAML frontmatter
2. Maps short model names to full provider IDs (e.g., `sonnet` -> `anthropic/claude-sonnet-4-6`)
3. Converts tool lists to OpenCode's boolean format (`{read: true, bash: true}`)
4. Inlines the markdown body as the agent's prompt
5. Collects `ai/rules/**/*.md` paths as instruction references
6. Merges the generated overlay into `opencode.json` (personal config wins on conflicts)

Dependencies: `bash`, `jq`, `sed` (no Python or yq needed).
