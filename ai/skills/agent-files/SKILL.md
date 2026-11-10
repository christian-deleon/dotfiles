---
name: agent-files
description: Author skills/agents/hooks/rules/MCP under ~/.dotfiles/ai/ for Grok, OpenCode, and Claude Code. Use for 'add a skill', 'new subagent', 'add a rule', 'add an MCP server', 'update the bash skill'. Not for `dot agent` project/env AGENTS overlays (see docs/dot-agent.md).
---

# Authoring AI Agent Files

> **Not `dot agent`.** This skill authors content under `~/.dotfiles/ai/`.
> Per-project / per-env AGENTS.md overlays are a different system — see
> [docs/dot-agent.md](../../../docs/dot-agent.md) and `dot agent`.

This repo is the **single source of truth** for three peer harnesses: Grok Build, OpenCode, and Claude Code. Each has its own installer that links or generates straight from `ai/` into its own tree; none reads another harness's files. The active profile's `items:` decides which harnesses a machine gets (`wsl-work` has no Claude). Grok's `[compat.claude]` stays off so Grok does not also scan the `~/.claude/` the Claude installer fills.

| Harness | Live path | Installer |
|---|---|---|
| **Grok Build** | `~/.grok/{skills,agents,hooks,rules}/`, `~/.grok/AGENTS.md`, `~/.grok/config.toml` | `install_ai_grok` |
| **OpenCode** | `~/.config/opencode/skills/<name>`, `AGENTS.md`; `opencode.json` agents/instructions/mcp | `install_ai_opencode` + `generate-opencode-config.sh` |
| **Claude Code** | `~/.claude/{skills,agents,rules}/`, `CLAUDE.md`; `settings.json` hooks; `~/.claude.json` `mcpServers` | `install_ai_claude` |

MCP roster: `~/.dotfiles/ai/mcp-servers.json.tpl`; the profile's `mcp:` block picks the servers and `generate_mcp_configs` writes that set to every enabled harness. Do not hand-edit `~/.claude.json`, `opencode.json` `mcp`, or Grok's `[mcp_servers.*]`.

## Decision tree

Pick the reference file that matches the artifact, read it first, then act:

| User wants to… | Read | Source dir |
|---|---|---|
| Create or update a skill | [skills.md](skills.md) | `~/.dotfiles/ai/skills/<name>/SKILL.md` |
| Create or update a subagent | [agents.md](agents.md) | `~/.dotfiles/ai/agents/<name>.md` |
| Create a slash command | [commands.md](commands.md) | Author as a skill — user-invocable skills **are** slash commands |
| Wire up a hook | [hooks.md](hooks.md) | `~/.dotfiles/ai/hooks/` |
| Add a rule / always-loaded instruction | [rules.md](rules.md) | `~/.dotfiles/ai/rules/<category>/<name>.md` |
| Add or edit an MCP server entry | [mcp.md](mcp.md) | `~/.dotfiles/ai/mcp-servers.json.tpl` |
| Apply changes to live config | [workflow.md](workflow.md) | body edits live; new items: `dot update`; MCP: `dot mcp-regen` |
| Mine this chat and optimize project and/or global agent context | `agent-optimize` skill | orchestrator → project files + this skill + `skill-review` |

Templates live in [`examples/`](examples/) — copy and edit, don't write from scratch.

## Universal rules

1. **Source of truth is always `~/.dotfiles/ai/`.** Never write to `~/.grok/skills` (etc.), `~/.config/opencode/`, or `~/.claude/` directly — those are install targets. If you're not in `~/.dotfiles/`, `cd` there first.

2. **After authoring, reconcile with the normal project path.** Existing skill/rule/agent files are already symlinked — body edits are live (restart the session if you changed a skill *description* so catalogs reload). **New** skills/agents/hooks/rules need a re-link; `dot update` does that (pull + `install_ai_<h>` for each enabled harness). For MCP roster or profile `mcp:` changes only: `dot mcp-regen`.

3. **Author for all three harnesses.** The body of any skill/agent/rule must read naturally in Grok, OpenCode, and Claude Code. Specifically:
   - Don't reference tools by brand. Say "the Read tool" or "the Bash tool", not "Grok's Read" or "OpenCode's bash".
   - Don't reference brand-specific UI affordances unless it's the only way to express the idea — and then name the harness (`grok inspect`, OpenCode Tab-cycle).
   - Don't pin to one harness's config file in the prose body (e.g. "edit `opencode.json`").
   - Harness-specific **frontmatter** is fine; each harness ignores keys it doesn't know. Subagents carry `tools:` plus OpenCode `permission:` / `mode:` where needed. Keep the body universal.
   - **Hook scripts are shared, registration is not.** Write the logic once under `ai/hooks/`, then register it for each harness — see [hooks.md](hooks.md).

4. **Mind the asymmetries** — these bite people:
   - **OpenCode has plugins, not hooks.** A shared hook script reaches OpenCode only through a plugin that calls it.
   - **Slash commands are skills.** Do not grow `ai/commands/`.
   - **All three auto-load project `AGENTS.md`.** The per-env overlay links into `~/.grok/AGENTS.md`, `~/.config/opencode/AGENTS.md`, and `~/.claude/CLAUDE.md` for each enabled harness. Do not author a project `CLAUDE.md` — if one sits next to `AGENTS.md`, Claude reads only the `CLAUDE.md`. Foreign repos may still have `CLAUDE.md` — migrate, don't author.

5. **Descriptions are triggers, not documentation.** Lead with the strongest use case, then 2–3 distinctive trigger phrases — not every variant. Aim for ~250–350 chars per skill. See [skills.md](skills.md).

6. **Don't invent fields.** Check the topic file before adding a new frontmatter key. Each harness ignores skill keys it doesn't recognize, so a harness-specific key on a shared `SKILL.md` is safe; it just does nothing elsewhere.

7. **Prefer editing existing files over creating new ones.** If a skill already exists for the topic, extend it. Only create a new skill/agent/rule when the responsibility is genuinely separate.

## Style conventions (this repo's voice)

Match the prevailing style of existing skills in `~/.dotfiles/ai/skills/`:

- **Open with a mental model paragraph.** One paragraph that frames what the tool is and isn't, before any tables or lists.
- **Call out the failure mode.** Many skills have a "the most common AI failure mode is X" sentence early. Use it when there's a stable mistake worth pre-empting.
- **Tables for schemas, code blocks for examples.** Don't prose-explain a frontmatter field if a table will do.
- **Direct and terse.** No "In this section we'll explore…". State the thing.

## When in doubt

Ask. The user knows their own conventions — when a request is ambiguous (user-level or project-level? extend an existing skill or create new?), ask one focused question before writing.
