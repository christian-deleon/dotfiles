---
name: agent-files
description: Author skills/agents/hooks/rules/MCP under ~/.dotfiles/ai/ for Grok (OpenCode is an adapter). Use for 'add a skill', 'new subagent', 'add a rule', 'add an MCP server', 'update the bash skill'. Not for `dot agent` project/env AGENTS overlays (see docs/dot-agent.md).
compatibility: opencode
---

# Authoring AI Agent Files

> **Not `dot agent`.** This skill authors content under `~/.dotfiles/ai/`.
> Per-project / per-env AGENTS.md overlays are a different system — see
> [docs/dot-agent.md](../../../docs/dot-agent.md) and `dot agent`.

This repo is the **single source of truth** for Grok Build configuration. OpenCode is a second-class adapter: it links at Grok's live tree where the format matches, and generates JSON only for shapes it cannot read.

| Tool | Live path | Mechanism |
|---|---|---|
| **Grok Build** (canonical) | `~/.grok/{skills,agents,hooks,rules}/`, `~/.grok/AGENTS.md`, `~/.grok/config.toml` | `install_ai_grok` + `generate_mcp_configs` |
| **OpenCode** (adapter) | `~/.config/opencode/skills` → `~/.grok/skills`; `AGENTS.md` hops at Grok; `opencode.json` agents/instructions/mcp | `install_ai_opencode` + generate scripts |

MCP roster: `~/.dotfiles/ai/mcp-servers.json.tpl` → live `~/.grok/config.toml` `[mcp_servers.*]` (canonical) and OpenCode `mcp` (adapter). Do not write `~/.claude.json`.

## Decision tree

Pick the reference file that matches the artifact, read it first, then act:

| User wants to… | Read | Source dir |
|---|---|---|
| Create or update a skill | [skills.md](skills.md) | `~/.dotfiles/ai/skills/<name>/SKILL.md` |
| Create or update a subagent | [agents.md](agents.md) | `~/.dotfiles/ai/agents/<name>.md` |
| Create a slash command | [commands.md](commands.md) | Author as a skill — Grok slash commands **are** skills |
| Wire up a hook | [hooks.md](hooks.md) | `~/.dotfiles/ai/hooks/` |
| Add a rule / always-loaded instruction | [rules.md](rules.md) | `~/.dotfiles/ai/rules/<category>/<name>.md` |
| Add or edit an MCP server entry | [mcp.md](mcp.md) | `~/.dotfiles/ai/mcp-servers.json.tpl` |
| Apply changes to live config | [workflow.md](workflow.md) | body edits live; new items: `dot update`; MCP: `dot mcp-regen` |
| Mine this chat and optimize project and/or global agent context | `agent-optimize` skill | orchestrator → project files + this skill + `skill-review` |

Templates live in [`examples/`](examples/) — copy and edit, don't write from scratch.

## Universal rules

1. **Source of truth is always `~/.dotfiles/ai/`.** Never write to `~/.grok/skills` (etc.) or `~/.config/opencode/` directly — those are install targets. If you're not in `~/.dotfiles/`, `cd` there first.

2. **After authoring, reconcile with the normal project path.** Existing skill/rule/agent files are already symlinked — body edits are live (restart the session if you changed a skill *description* so catalogs reload). **New** skills/agents/hooks/rules need a re-link; `dot update` already does that (pull + `install_ai_grok` + OpenCode adapter). For MCP template changes only: `dot mcp-regen`.

3. **Author for Grok.** The body of any skill/agent/rule must read naturally in Grok. OpenCode consumes the same files via the adapter. Specifically:
   - Don't reference tools by brand. Say "the Read tool" or "the Bash tool", not "Grok's Read" or "OpenCode's bash".
   - Don't reference brand-specific UI affordances unless it's the only way to express the idea — and then call out the tool (`grok inspect`, OpenCode Tab-cycle).
   - Don't pin to adapter config files in the prose body (e.g. don't say "edit `opencode.json`" when the user is on Grok).
   - Tool-specific **frontmatter** is fine. Use `compatibility: opencode` on skills so the adapter surfaces them. Use Grok-shaped `tools:` on subagents; add OpenCode `permission:` / `mode:` when the adapter needs them. Keep the body universal.
   - **Hooks are Grok-only.** OpenCode has plugins, not hooks. Write the logic as a script under `ai/hooks/` with an event-prefixed filename.

4. **Mind the asymmetries** — these bite people:
   - **OpenCode has no hooks.** `ai/hooks/` is ignored by OpenCode.
   - **Grok slash commands are skills.** Do not grow `ai/commands/`.
   - **Grok and OpenCode both auto-load project `AGENTS.md`.** Env overlay lives at `~/.grok/AGENTS.md`; OpenCode hops at that file. Foreign repos may still have `CLAUDE.md` — migrate, don't author.

5. **Descriptions are triggers, not documentation.** Lead with the strongest use case, then 2–3 distinctive trigger phrases — not every variant. Aim for ~250–350 chars per skill. See [skills.md](skills.md).

6. **Don't invent fields.** Check the topic file before adding a new frontmatter key. OpenCode **ignores** unknown skill keys (it used to Zod-fail — current docs say ignored). Extra Grok fields on a shared `SKILL.md` are therefore safe for the adapter; they just do nothing there.

7. **Prefer editing existing files over creating new ones.** If a skill already exists for the topic, extend it. Only create a new skill/agent/rule when the responsibility is genuinely separate.

## Style conventions (this repo's voice)

Match the prevailing style of existing skills in `~/.dotfiles/ai/skills/`:

- **Open with a mental model paragraph.** One paragraph that frames what the tool is and isn't, before any tables or lists.
- **Call out the failure mode.** Many skills have a "the most common AI failure mode is X" sentence early. Use it when there's a stable mistake worth pre-empting.
- **Tables for schemas, code blocks for examples.** Don't prose-explain a frontmatter field if a table will do.
- **Direct and terse.** No "In this section we'll explore…". State the thing.
- **`compatibility: opencode`** belongs in every skill's frontmatter unless the skill explicitly should not surface in OpenCode.

## When in doubt

Ask. The user knows their own conventions — when a request is ambiguous (user-level or project-level? extend an existing skill or create new?), ask one focused question before writing.
