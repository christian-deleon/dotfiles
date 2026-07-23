---
name: agent-optimize
description: Mine this conversation and optimize AI agent context in the current project and/or global user config. Use when the user says /agent-optimize, 'optimize agent context', 'capture what I had to explain', or 'update skills/rules from this chat'. Skips one-offs.
compatibility: opencode
argument-hint: "[optional focus]"
---

# Agent Optimize

Mine the **current conversation** for durable lessons — corrections, repeated explanations, outdated guidance, missing conventions — and write them into the right **agent context files**, wherever those live for this session:

1. **Project scope** — the repo (or workspace) the agent is working in
2. **Global scope** — the user's shared agent stack (for this user: `~/.dotfiles/ai/` and related overlays)

This skill is **project-agnostic**. It is not limited to the dotfiles repo. Run it from any project, anytime the user asks. It is an **orchestrator**: discover surfaces, triage findings, propose a change set, apply only after accept.

The most common failure mode is **scope mistake + overfitting** — putting a repo-only convention into a global skill, or a one-off preference into permanent config. Prefer "no change" or skip-with-reason over a weak edit.

## Scope model

Every finding gets a **scope** and a **surface**.

| Scope | Meaning | Typical surfaces |
|---|---|---|
| **Project** | True only for this repo / product | See discovery list below under the project root |
| **Global** | Should apply across projects / all sessions | User-level skills, rules, agents, env AGENTS |
| **Skip** | One-off, model error, or already covered | No write |

**Default:** if the lesson is about *this codebase's* layout, commands, conventions, or architecture → **project**. If it is a personal workflow, tool preference, or reusable skill the user wants everywhere → **global**. When unclear, **ask** before writing.

### Project surfaces (discover these)

From the project root (walk up from cwd to the git root if needed), look for what actually exists — do not assume a layout:

| Surface | Common paths |
|---|---|
| Agent instructions | `AGENTS.md`, `AGENTS.override.md`, `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, nested dir-level `AGENTS.md` / `CLAUDE.md` |
| Rules | `.claude/rules/**/*.md`, project rules dirs the repo already uses |
| Project skills | `.claude/skills/**`, `.agents/skills/**`, or other skill dirs the project documents |
| Tool config | `opencode.json` / `.opencode/` instructions, Cursor/Codex rule files if present and in use |
| Private overlay | Symlinked `AGENTS.md` / `CLAUDE.md` managed by `dot agent` (canonical content may live under `~/.dotfiles/agent-files/projects/<name>/`) |

Edit the **canonical** file: if `AGENTS.md` is a symlink, write through to (or open) its target — do not replace a managed symlink with a plain file unless the user asks.

Prefer the project's established pattern:

- Checked-in `AGENTS.md` (+ thin `CLAUDE.md` with `@AGENTS.md` when Claude must load it) when the team commits agent context
- `dot agent` overlays when the project deliberately keeps agent files out of git
- Do not invent a new layout when one already exists

### Global surfaces (this user's stack)

| Surface | Canonical source | Do **not** edit |
|---|---|---|
| Shared skills | `~/.dotfiles/ai/skills/<name>/` | Tool install dirs (`~/.claude/skills/`, `~/.grok/skills/`, `~/.config/opencode/skills/`) — those are symlinks/install targets |
| Shared rules | `~/.dotfiles/ai/rules/` | Same: edit source, not install copies |
| Shared agents / MCP | `~/.dotfiles/ai/agents/`, `~/.dotfiles/ai/mcp-servers.json.tpl` | Generated or symlinked tool configs |
| Env-level AGENTS | `dot agent env` → `~/.dotfiles/agent-files/env/<name>/AGENTS.md` | Unmanaged copies at tool entrypoints if they are symlinks into that tree |

If the session is **inside** `~/.dotfiles` itself, project and global can overlap — still classify each finding: repo architecture docs vs shared AI skills vs personal env context.

### Related skills (by name, not path)

Load these when applying a finding — they are separate skills in the catalog, not relative files:

| Finding | Load / follow |
|---|---|
| Fix an **existing global** skill | `skill-review` |
| Author new global skill / rule / agent / command / MCP | `agent-files` |
| Project-only instruction file | Edit the project's surface directly (no need for `agent-files` unless creating a *global* artifact) |
| Untracked project AGENTS managed out-of-repo | `dot agent` (`dot agent link`, etc.) |

## When to invoke

Fire when the user:

- Says `/agent-optimize`, "optimize agent context", "optimize skills/rules", "capture what I had to explain"
- Asks to update agent memory / AI config from **this chat** without naming a single file
- Wants a pass over what felt wrong or missing in the conversation (project and/or global)

Do **not** fire when:

- They already know which **global skill** is wrong → `skill-review`
- They want a brand-new **global** artifact with a clear brief → `agent-files`
- They want to hand work to another session → `handoff`
- Nothing durable came up

Optional `$ARGUMENTS` narrows focus (e.g. `project only`, `global skills`, `AGENTS.md`, a skill name).

## Workflow

### 1. Establish workspace roots

1. Resolve **project root** (git root from cwd, or the workspace root the session is in).
2. Note **global AI root** when relevant: `~/.dotfiles/ai/` for this user.
3. Inventory agent context files that exist (project list above + global skills/rules if findings might be global). Do not scan the entire home directory — only known agent surfaces.

### 2. Mine the conversation

Scan **this chat** (not prior sessions unless the user pastes them):

| Signal | Example |
|---|---|
| **User correction** | "No, use X not Y" / "we always do Z" |
| **Repeated re-prompt** | Same clarification more than once |
| **Missing knowledge** | User explained a workflow, domain fact, or convention the agent lacked |
| **Wrong / stale guidance** | Skill, rule, or AGENTS text was outdated or never fired |
| **Wrong surface / scope** | Content is in global when it should be project (or the reverse) |

Ignore pure task progress, transient debugging, and secrets/tokens.

If `$ARGUMENTS` is set, only collect findings in that scope.

### 3. Classify each finding

| Class | Scope | Destination |
|---|---|---|
| **Project instructions** | Project | Existing `AGENTS.md` / `CLAUDE.md` / override, or create only if the project has no agent file and the user wants one |
| **Project rule / skill** | Project | Project rules or skills dirs that already exist (or the repo's documented convention) |
| **Global skill fix** | Global | Existing skill under `~/.dotfiles/ai/skills/<name>/` via `skill-review` discipline |
| **New global skill** | Global | `agent-files` |
| **Global rule** | Global | `~/.dotfiles/ai/rules/...` — short, always-on only |
| **Env AGENTS** | Global (machine) | `dot agent env` content |
| **Model error** | — | No edit — skill/file already correct; model ignored it |
| **One-off / skip** | — | No edit |

**Prefer project over global** when the lesson only matters in this repo.  
**Prefer skills over always-on rules** when the topic is on-demand.  
**Prefer extending an existing file** over creating a new one.  
**Default to skip when uncertain.**

### 4. Deduplicate and read targets

Before proposing writes:

1. Map each finding to a concrete path (project inventory or global skill/rule).
2. Read the target end-to-end — the fix is often already there.
3. Merge findings that hit the same file.
4. Drop already-covered items; flag contradictions for the user.

### 5. Present a change set (before any write)

```markdown
## Agent optimize — proposed changes

| # | Scope | Class | Target | Change (1 line) | Evidence |
|---|---|---|---|---|---|
| 1 | Project | Instructions | `AGENTS.md` | … | User said "…" |
| 2 | Global | Skill fix | `~/.dotfiles/ai/skills/flux/` | … | … |
| 3 | — | Skip | — | Model error: already documented | … |

Apply all / apply #N / skip all?
```

For each accepted item, show a **diff-style preview** (old → new, or full draft for new files) before writing. Walk multi-file changes item by item.

Empty table → "Nothing durable to capture" and stop. That is success.

### 6. Apply accepted items

| Class | How |
|---|---|
| Project instructions / rules / skills | Edit the project's canonical path; preserve symlink targets for `dot agent`-managed files |
| Global skill fix | Follow `skill-review` (minimal edit, source under `~/.dotfiles/ai/skills/` only) |
| New global skill / rule / agent / MCP | Follow `agent-files` |
| Env / private project overlay | Update canonical overlay; use `dot agent link` / `dot agent env link` when setup is missing |
| Model error / skip | Report only |

**Batching:** multiple accepted items OK if each has a clear preview. Smallest change that captures the lesson.

### 7. Reconcile

| Change | Follow-up |
|---|---|
| Project file already in the repo | Done; user commits if they want |
| Global body-only skill/rule (already symlinked) | Live; no install |
| **New** global skill/rule/agent path | Remind: `dot update` |
| Global skill **description** change | Restart session so catalogs reload |
| MCP template | `dot mcp-regen` |

Do not auto-commit unless the user asks.

## Decision shortcuts

| Situation | Action |
|---|---|
| "In this repo we do X" | Project `AGENTS.md` / project rules — not global |
| "I always want agents to do X" | Global skill or short global rule |
| Named global skill was wrong | Global skill fix (`skill-review` rules) |
| Explained a multi-step personal workflow | New or extended **global** skill |
| Explained this product's domain / deploy path | **Project** instructions |
| "On this locked-down machine…" | Env AGENTS via `dot agent env` |
| Skill/file said the right thing; model ignored it | Model error — no edit |
| Mild one-time preference | Skip or ask |

## Rules

- **Any project.** Discover local agent files; never assume the cwd is `~/.dotfiles`.
- **Scope before surface.** Project vs global first, then which file.
- **Propose first, write after accept.**
- **Conversation evidence only.**
- **Absolute or repo-root paths in the change table** — never skill-relative links like `../other-skill/`.
- **Smallest durable capture.**
- **No secrets** in any agent file.
- **No personal anecdotes as policy** — rephrase as a convention or skip.
- **Empty is fine.**

## Anti-patterns

- Relative markdown links into the skill package as if the user were browsing the repo tree.
- Dumping every correction into global rules.
- Writing global skills for repo-only facts (or project AGENTS for personal cross-repo prefs).
- Editing tool install/symlink directories instead of canonical sources.
- Creating a new agent layout in a project that already has one.
- Speculative "optimizations" without chat evidence.
- Auto-firing without the user asking.
