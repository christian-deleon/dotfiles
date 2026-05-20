---
name: skill-review
description: Review and refine an EXISTING skill in ~/.dotfiles/ai/skills/ after the user noticed friction or a wrong recommendation. Use when the user invokes /skill-review, says 'that skill was wrong', 'update the X skill', 'this skill needs to mention', 'I keep having to tell you', or 'this should be in a skill'. For brand-new skills, use `agent-files` instead.
compatibility: opencode
argument-hint: "[what felt wrong]"
---

# Skill Review

Diagnose and refine an existing skill after a session where the agent produced output the user disagreed with, missed an edge case, or had to be re-prompted on something the skill should have covered. This skill **updates existing skills only** — to author a new skill from scratch, use the `agent-files` skill.

> **CRITICAL: One moment of friction is not always a pattern.**
> Distinguish "the skill was wrong / missing" from "I just wanted something different this time."
> Don't bloat a skill with edge cases that don't generalize.
> When in doubt, propose the smallest possible change and call out your uncertainty.

## When to invoke

Fire this skill when:

- A skill recommended something the user corrected ("no, use X instead").
- The user said the same correction more than once in a session.
- A skill description didn't trigger when it should have, or triggered when it shouldn't have.
- The user asked for behavior that *should* be in an existing skill but isn't there yet.
- The user explicitly says "update the X skill", "/skill-review", or "this should be in a skill".

Do NOT fire this skill when:

- The user wants a brand new skill — use the `agent-files` skill instead.
- The change is a one-off preference that doesn't generalize to future sessions.
- The friction was a model mistake, not a skill gap (the skill said the right thing and the model ignored it — flag that to the user but don't edit the skill).

## Workflow

### 1. Identify the target skill

Sources, in order of preference:

1. The user's hint (`$ARGUMENTS`) — direct mention of a skill name or topic.
2. Recent transcript — scan for skill invocations, corrections, or repeated re-prompting on the same topic.
3. `ls ~/.dotfiles/ai/skills/` to enumerate options if nothing else narrows it.

If you can't identify the target with confidence after the above, **ask the user** which skill or topic needs review. Do not guess.

### 2. Read the skill end-to-end

Read the target `SKILL.md` and any companion `.md` files **before** proposing changes. The fix is often already in the skill, just in a section you didn't expect. Use the Read tool on the actual file in `~/.dotfiles/ai/skills/<name>/`, not the symlinked target.

### 3. Diagnose the gap

Classify the problem. Pick the primary class even if multiple apply:

| Class | Symptom | Likely fix |
|---|---|---|
| **Wrong fact** | Skill recommends X, user uses Y | Replace X with Y in the relevant section |
| **Missing edge case** | Skill covers the common case but missed one | Add a row to a table or a short paragraph — resist adding a whole new section |
| **Weak trigger** | Skill should have fired but didn't | Edit the `description` field — add the phrase or file type that didn't match |
| **Wrong scope** | Content is in skill A but really belongs in skill B | Propose moving it; flag the cross-skill impact |
| **Bloat** | `SKILL.md` is over 500 lines or covers multiple distinct topics | Propose a split into companion files (see `agent-files` skill) |
| **Stale convention** | Skill reflects an old preference the user has moved past | Update or remove; explain what changed |
| **Model error, not skill gap** | Skill says the right thing, model didn't follow it | No edit — surface this to the user instead |

### 4. Propose the edit

Present the proposed change as a **diff-style preview** before writing:

- Quote the existing text you'd change (file + section header or line range).
- Show the new text.
- Explain in one sentence *why* — what session evidence supports this change.

Keep edits **minimal**. Prefer 1–5 line additions or replacements over rewriting a section. If the change is bigger than that, walk through it section by section rather than dumping a full rewrite. Larger restructurings (splits, moves between skills) should be confirmed step by step.

### 5. Confirm and apply

After the user accepts, use the Edit tool against the file in `~/.dotfiles/ai/skills/<name>/`. **Never edit the symlinked targets** under `~/.claude/skills/`, `~/.config/opencode/skills/`, or `~/.grok/skills/` — the installer will overwrite them.

Validation checks before writing:

- If `description` changed, the combined `description + when_to_use` must stay under 1,536 chars (Claude Code cap). OpenCode caps `description` at 1,024.
- If you added or changed a frontmatter key, verify it's in the schema (see the `agent-files` skill's `skills.md`). OpenCode rejects unknown keys via Zod.
- If the skill is now over 500 lines after the edit, suggest splitting in a follow-up turn.

### 6. Remind to install

End with: *"Run `dot install` to refresh symlinks across all three tools. No restart needed for Claude Code or Grok; OpenCode picks up changes on the next session."*

## Rules

- **Edit at the source.** Always write to `~/.dotfiles/ai/skills/`, never the symlinked tool dirs.
- **Smallest diff that fixes it.** Don't rewrite sections when a sentence change will do.
- **Preserve voice.** Match the skill's existing tone — most use the "Use when…" or "ALWAYS use when…" idiom, terse tables, fenced examples.
- **Don't invent frontmatter fields.** OpenCode rejects unknown keys. See the `agent-files` skill for the schema.
- **Flag conflicts.** If the new rule contradicts an existing rule in the skill, surface the conflict before editing — don't quietly bury contradictions.
- **One skill at a time.** If multiple skills need updates, do them in separate turns so each diff is reviewable.
- **Distinguish skill gaps from model errors.** If the skill already said the right thing, no edit is needed — tell the user instead.

## Anti-patterns

- Editing the symlinked target (`~/.claude/skills/<name>/SKILL.md`) — the installer will overwrite it on the next run.
- Adding a personal anecdote ("user once said…") to a skill — skills are general; private context goes in `~/.localrc` or `~/.gitconfig.local`.
- Updating a skill based on a single moment of friction without checking whether the existing skill already covers the case (it often does, just not where you looked first).
- Rewriting a skill's whole structure when the actual problem is one wrong fact.
- Bloating the `description` field with every phrase you can think of — keep triggers focused; the model fuzzy-matches.
- Forgetting the `dot install` reminder.
