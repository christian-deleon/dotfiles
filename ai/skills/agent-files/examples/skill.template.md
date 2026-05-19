---
name: my-skill
description: One-sentence summary of what this skill does. ALWAYS use when [list specific file types / paths / phrases that should fire it], or for prompts like 'add a foo', 'fix the bar', 'how do I baz'. Enforces / covers / documents [whatever the body delivers].
compatibility: opencode
---

# My Skill

One-paragraph mental model — what this is for, what it covers, what it explicitly does not cover.

The most common AI failure mode here is [a stable mistake worth pre-empting]. [What to do instead.]

## Core concept / section heading

[Body content, written for "the agent" — no tool-brand references in the prose. Use plain English for tool names: "the Read tool", "the Bash tool", "spawn a subagent".]

| Field | Notes |
|---|---|
| Use tables | For schemas and option lists |
| Use code blocks | For examples |

```bash
# Concrete example
some-command --flag value
```

## Another section

More content. Keep `SKILL.md` under ~500 lines. For deeper content, split into sibling reference files:

- For X, read `x.md`.
- For Y, read `y.md`.

Then put `x.md` and `y.md` next to `SKILL.md` in the same directory.
