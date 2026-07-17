---
name: agent-files
description: Author skills/agents/hooks/rules/MCP under ~/.dotfiles/ai/ for Claude Code, OpenCode, and Grok. Use for 'add a skill', 'new subagent', 'add a rule', 'add an MCP server', 'update the bash skill'. Not for `dot agent` project/env AGENTS overlays (see docs/dot-agent.md).
compatibility: opencode
---

# Authoring AI Agent Files

> **Not `dot agent`.** This skill authors content under `~/.dotfiles/ai/`.
> Per-project / per-env AGENTS.md overlays are a different system — see
> [docs/dot-agent.md](../../../docs/dot-agent.md) and `dot agent`.

This dotfiles repo is the **single source of truth** for AI agent configuration across three terminal coding agents:

| Tool | Reads from | Mechanism |
|---|---|---|
| **Claude Code** | `~/.claude/{agents,commands,skills,rules}/` | Symlinked from `~/.dotfiles/ai/<type>/` by `install_ai_claude` |
| **OpenCode** | `~/.config/opencode/{commands,skills}/`, `opencode.json` | Symlinks + `generate-opencode-config.sh` merges agents/rules into JSON |
| **Grok Build** | `~/.grok/{skills,agents,hooks}/` | Symlinked from `~/.dotfiles/ai/<type>/` by `install_ai_grok` |

MCP entries are shared across all three via `~/.dotfiles/ai/mcp-servers.json.tpl` → generated into `~/.claude.json` (used by Claude Code + Grok compat) and `~/.config/opencode/opencode.json`.

## Decision tree

Pick the reference file that matches the artifact, read it first, then act:

| User wants to… | Read | Source dir |
|---|---|---|
| Create or update a skill | [skills.md](skills.md) | `~/.dotfiles/ai/skills/<name>/SKILL.md` |
| Create or update a subagent | [agents.md](agents.md) | `~/.dotfiles/ai/agents/<name>.md` |
| Create or update a slash command | [commands.md](commands.md) | `~/.dotfiles/ai/commands/<name>.md` |
| Wire up a hook | [hooks.md](hooks.md) | `~/.dotfiles/ai/hooks/` (Grok) or `~/.claude/settings.json` (Claude) |
| Add a rule / always-loaded instruction | [rules.md](rules.md) | `~/.dotfiles/ai/rules/<category>/<name>.md` |
| Add or edit an MCP server entry | [mcp.md](mcp.md) | `~/.dotfiles/ai/mcp-servers.json.tpl` |
| Apply changes to live config | [workflow.md](workflow.md) | body edits live; new items: `dot update`; MCP: `dot mcp-regen` |

Templates live in [`examples/`](examples/) — copy and edit, don't write from scratch.

## Universal rules

1. **Source of truth is always `~/.dotfiles/ai/`.** Never write to `~/.claude/`, `~/.config/opencode/`, or `~/.grok/` directly — those paths are populated by symlinks and the installer will overwrite anything you put there. If you're not in `~/.dotfiles/`, `cd` there first.

2. **After authoring, reconcile with the normal project path.** Existing
   skill/rule/agent files are already symlinked — body edits are live on
   disk (restart the session if you changed a skill *description* so
   catalogs reload). **New** skills/agents/commands need a re-link, and
   `dot update` already does that (pull + re-link Claude/OpenCode/Grok AI
   assets + OS packages). Prefer that over inventing special AI-only
   install paths. For MCP template changes only: `dot mcp-regen`.

3. **Author tool-agnostic content.** Every file you write here gets installed into all three tools simultaneously. Christian uses all three (Claude Code, OpenCode, Grok), so the **body** of any skill/agent/command/rule must read naturally regardless of which tool is consuming it. Specifically:
   - Don't reference tools by brand. Say "the Read tool" or "the Bash tool", not "Claude Code's Read" or "OpenCode's bash".
   - Don't reference brand-specific UI affordances ("type `/agents`", "press Tab to cycle agents") unless it's the only way to express the idea — and then call out the tool.
   - Don't pin to brand-specific config files in the prose body (e.g. don't say "edit your `~/.claude.json`" when the user might be on OpenCode).
   - Tool-specific **frontmatter** is fine — each tool ignores keys it doesn't understand. Use `compatibility: opencode` on skills, Claude-Code-shaped `tools:` on subagents, etc. Just keep the body universal.
   - **Hooks are the exception.** Hooks are inherently tool-specific (Claude JSON, Grok TOML, OpenCode TypeScript). When the goal is cross-tool, write the **logic** as a portable script and write three thin wrappers — see [hooks.md](hooks.md).

4. **Mind the asymmetries** — these bite people. The reference files cover them in detail, but the headlines:
   - **Claude Code hooks** live in `settings.json` (not under `ai/hooks/`). `ai/hooks/` only flows to Grok.
   - **OpenCode has no hooks** — it uses TypeScript plugins. `ai/hooks/` is ignored by OpenCode.
   - **Claude Code merged slash commands into skills.** `ai/commands/<name>.md` still works there but skills are preferred. OpenCode keeps `commands/` separate; Grok has no native commands dir (author as skills).
   - **AGENTS.md is NOT auto-loaded by Claude Code.** Use a `CLAUDE.md` that does `@AGENTS.md` if you want both tools to read the same file. OpenCode and Grok do auto-load `AGENTS.md`.

5. **Descriptions are triggers, not documentation.** A skill/agent description is what the model uses to decide whether to fire. Lead with the strongest use case, then 2-3 distinctive trigger phrases — not every variant. Aim for ~250-350 chars per skill: Claude Code packs all installed skill descriptions into one listing budget (default 1% of context, ~8,000 chars) and drops the long ones when it overflows. See [skills.md](skills.md) for the full pattern and anti-patterns.

6. **Don't invent fields.** Each tool has a strict frontmatter schema — fields not in the reference file will be silently ignored (or, in OpenCode's case, fail Zod validation). When in doubt, check the topic file before adding a new key.

7. **Prefer editing existing files over creating new ones.** If a skill already exists for the topic, extend it. Only create a new skill/agent/rule when the responsibility is genuinely separate.

## Style conventions (this repo's voice)

Match the prevailing style of existing skills in `~/.dotfiles/ai/skills/`:

- **Open with a mental model paragraph.** One paragraph that frames what the tool is and isn't, before any tables or lists.
- **Call out the failure mode.** Many skills have a "the most common AI failure mode is X" sentence early. Use it when there's a stable mistake worth pre-empting.
- **Tables for schemas, code blocks for examples.** Don't prose-explain a frontmatter field if a table will do.
- **Direct and terse.** No "In this section we'll explore…". State the thing.
- **`compatibility: opencode`** belongs in every skill's frontmatter unless the skill explicitly should not surface in OpenCode.

## When in doubt

Ask. The user knows their own conventions — when a request is ambiguous (which tool? user-level or project-level? extend an existing skill or create new?), ask one focused question before writing.
