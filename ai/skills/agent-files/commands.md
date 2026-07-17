# Slash Commands

A **slash command** is a user-invoked prompt template — `/foo` types the body of `foo.md` into the conversation, with `$ARGUMENTS` and friends substituted, then sends it. Unlike skills (which the model can auto-invoke based on the description), slash commands are explicit user actions.

The most common AI failure mode here is reaching for a slash command when a skill would be better. Skills auto-fire on the right context; commands only run when the user types `/name`. **Default to authoring skills unless the workflow specifically benefits from being explicit-only.**

## Status across tools

| Tool | Native commands dir? | Recommendation |
|---|---|---|
| **Claude Code** | Yes, but **merged into skills** — `~/.claude/commands/<name>.md` still works, skills are preferred | Author as a skill (`disable-model-invocation: true` makes it user-only) |
| **OpenCode** | Yes — `~/.config/opencode/command/` or `commands/` | Native commands are fine here |
| **Grok Build** | No native dir documented | Author as a skill — user-invocable skills auto-expose as `/<name>` |

This repo keeps `ai/commands/` as the source dir, symlinked into Claude Code and OpenCode. Grok ignores it. If you want a slash command in all three tools, author it as a skill in `ai/skills/<name>/SKILL.md` with `disable-model-invocation: true` (Claude) — that's the most portable shape.

## Where commands live

```
~/.dotfiles/ai/commands/<name>.md
```

Symlinked into:

| Tool | Path |
|---|---|
| Claude Code | `~/.claude/commands/<name>.md` |
| OpenCode | `~/.config/opencode/commands/<name>.md` (plural — installer-generated) |

Grok does not consume `ai/commands/`. Author Grok-visible commands as skills.

## Filename → slash command

`commands/foo.md` → `/foo`. Subdirectory namespacing:

| Tool | Behavior |
|---|---|
| Claude Code (user/project) | Flat — `commands/foo/bar.md` resolves as `/bar` |
| Claude Code (plugin) | Namespaced — `plugin/commands/foo/bar.md` is `/plugin:foo:bar` |
| OpenCode | Flat — filename only |

Practical rule: **don't rely on subdirectory namespacing.** Put commands at the top level of `ai/commands/`.

## Frontmatter

```yaml
---
description: ...                # Required everywhere; shown in autocomplete
argument-hint: "[issue]"        # Claude Code: hint shown next to /command in picker

# Claude Code-specific:
allowed-tools: Bash(git diff)   # Pre-approve tools (string globs)
model: inherit                  # Override model for this command
disable-model-invocation: true  # User-only; model can't suggest it (skill-equivalent only)

# OpenCode-specific:
agent: build                    # Run the command under this named agent
model: anthropic/claude-sonnet-4-6  # Override model
subtask: true                   # Force invocation as a subagent
---
```

Body = the prompt template (see "Substitution" below).

## Substitution

Both Claude Code and OpenCode expand the following inside the body before sending to the model:

| Token | Expands to |
|---|---|
| `$ARGUMENTS` | All args typed after the command |
| `$1`, `$2`, … `$9` | Positional args |
| `$ARGUMENTS[N]` | Same as `$N` (Claude Code) |
| `$<name>` | Named arg from frontmatter `arguments: [...]` (Claude Code skills/commands) |
| `` !`cmd` `` (inline) | Run shell; substitute stdout |
| ` ```! ` block ` ``` ` | Multi-line shell exec; substitute stdout |
| `@path/to/file` | Inline file contents (OpenCode body, Claude Code memory imports) |

Shell exec runs **before** the model sees the body — so the model receives the output, not the command. This is the main reason commands are useful: they pre-bake context (diffs, git log, file listings) into the prompt.

### Example: pre-baked diff context

```markdown
---
description: Suggest a commit message for the current staged diff
argument-hint: "[extra context]"
allowed-tools: Bash(git diff)
---

Recent commits for style reference:

```!
git log --oneline -10
```

Staged changes:

```!
git diff --staged
```

Suggest a Conventional Commits message. Extra context: $ARGUMENTS
```

## Portability — body must be tool-agnostic

Commands in `~/.dotfiles/ai/commands/` get symlinked into Claude Code AND OpenCode (Grok doesn't have a native commands dir — it surfaces user-invocable skills as slash commands instead). The body of the command — the prompt template the model receives — needs to be tool-agnostic.

| Do this | Not this |
|---|---|
| "Summarize the diff using the Read and Grep tools as needed" | "Use Claude Code's Read tool…" |
| Frontmatter: `description`, `argument-hint` | Frontmatter that hardcodes a tool-specific behavior |

Substitutions (`$ARGUMENTS`, `!`cmd``, `@file`) work the same in both tools — use them freely. The body should read naturally regardless of which tool fires the command.

## When to use a command vs a skill

| Use a **slash command** when | Use a **skill** when |
|---|---|
| The workflow is user-initiated and shouldn't auto-fire | The workflow should auto-fire when the model sees relevant context |
| You want pre-baked shell output (diffs, status, logs) in every invocation | You want a reference document the model reads on demand |
| It's a one-shot prompt template, not a multi-page guide | It's a body of knowledge with progressive disclosure |
| Three tools matter less (Grok lacks native commands) | All three tools should pick it up |

For Christian's setup, **skills are the default**. The existing repo has many skills and zero `ai/commands/*.md` entries — that's intentional.

## Minimal canonical example

See [`examples/command.template.md`](examples/command.template.md).

```markdown
---
description: Summarize the current branch's diff vs main
argument-hint: "[focus area]"
allowed-tools: Bash(git diff)
---

Diff vs main:

```!
git diff main...HEAD
```

Summarize what changed. Focus area (optional): $ARGUMENTS
```

## Per-tool gotchas

### Claude Code
- Commands and skills share the same frontmatter. A skill named `commit` and a command named `commit` both resolve as `/commit`; the **skill wins**.
- `disable-model-invocation: true` on a skill makes it user-only (acts like a command).
- Subdirectories don't namespace for user/project — `commands/foo/bar.md` is `/bar`, not `/foo:bar`.

### OpenCode
- Both `command/` and `commands/` directory names work (the glob accepts `{command,commands}`). Stick with `commands/` for consistency with this repo.
- Inline-in-`opencode.json` commands also work but are messier to maintain — markdown files are the recommended shape.
- `agent:` lets you scope the command to run under a specific subagent — useful for "always run with the reviewer".

### Grok
- No native commands. Author as a user-invocable skill; `/<skill-name>` becomes the slash command.

## Editing an existing command

Same workflow as skills/agents — edit `ai/commands/<name>.md`. Body edits live via symlink; new commands need `dot update`. Restart if the catalog must reload.
