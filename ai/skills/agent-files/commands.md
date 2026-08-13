# Slash Commands

A **slash command** is a user-invoked prompt template — `/foo` types a body into the conversation, with `$ARGUMENTS` and friends substituted, then sends it. Unlike skills (which the model can auto-invoke from the description), a user-only command runs only when the user types `/name`.

The most common AI failure mode here is reaching for a dedicated commands file when a skill would be better. **In this repo, Grok slash commands are skills.** Set `disable-model-invocation: true` if the workflow must be explicit-only.

## Status

| Tool | How to get `/name` |
|---|---|
| **Grok** | User-invocable skill at `ai/skills/<name>/SKILL.md` → `/<name>` |
| **OpenCode** | Same skill via the adapter symlink; also has a native `commands/` dir we do **not** grow |

`ai/commands/` is gone on purpose. Don't recreate it. See [`examples/command.template.md`](examples/command.template.md) only as a **prompt-template** example to paste into a skill body.

## Substitution (useful in user-invocable skills)

| Token | Expands to |
|---|---|
| `$ARGUMENTS` | All args typed after `/name` |
| `$1`, `$2`, … `$9` | Positional args |
| `` !`cmd` `` (inline) | Run shell; substitute stdout |
| ` ```! ` block ` ``` ` | Multi-line shell exec; substitute stdout |

Shell exec runs **before** the model sees the body — so the model receives the output, not the command. That's the main reason a user-only skill is useful: pre-bake diffs, git log, file listings.

### Example: pre-baked diff context (as a skill)

```markdown
---
name: commit-msg
description: Suggest a commit message for the current staged diff. User-invoked via /commit-msg.
compatibility: opencode
disable-model-invocation: true
argument-hint: "[extra context]"
allowed-tools: Bash
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

## When to use a user-only skill vs a normal skill

| User-only (`disable-model-invocation: true`) | Normal skill |
|---|---|
| Workflow is user-initiated and shouldn't auto-fire | Workflow should auto-fire on relevant context |
| You want pre-baked shell output in every invocation | You want a reference document the model reads on demand |
| It's a one-shot prompt template | It's a body of knowledge with progressive disclosure |

For this setup, **normal skills are the default**. User-only is the exception.

## Per-tool gotchas

### Grok
- No separate commands directory. `/<skill-name>` is the slash command.
- Collisions with built-ins get a qualified name (`/user:commit`).
- `user-invocable: false` hides it from the slash menu but the model can still invoke it. That's the opposite of `disable-model-invocation`.

### OpenCode
- Native `command/` / `commands/` dirs exist; we don't install into them.
- `agent:` on a native command can scope it to a named agent — not something this repo authors.

## Editing

Same as skills — edit `ai/skills/<name>/SKILL.md`. Body edits live via symlink; new skills need `dot update`.
