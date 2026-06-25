---
name: handoff
description: Capture the current problem and what we've found into a lean, copy-pasteable blob to transfer to another session. Use when the user says /handoff, 'hand this off', 'capture this for another session', 'dump this problem so I can paste it elsewhere', or wants to move an in-progress investigation without writing a full report.
compatibility: opencode
argument-hint: "[which problem]"
---

# Handoff

A handoff distills the problem you just hit and what you've learned about it into the smallest blob that lets a fresh session pick up the chase. It is **not** a status report — no dates, no next-steps, no open-questions, no metadata ceremony. Just two things: what's wrong, and what we found. The output is meant to be copy-pasted into another session, so it has to stand alone.

The most common failure mode is padding it into a giant report. Resist. Two sections, anchored with `file:line`, nothing else.

## Gather context first, then write

A handoff is only as good as what it captures — a confident but wrong blob sends the next session down the wrong path. Before writing, check whether you actually have the details to describe the problem accurately. If the context is thin, **gather it first** rather than emitting something vague or speculative:

- Haven't opened the file you're about to cite? Read it and get the real `file:line`.
- Only have the error second-hand? Find or reproduce the exact message, command, or output.
- Unsure how the pieces connect? Trace it until the cause-or-suspicion is grounded in something you've seen, not guessed.

Only once you're confident the problem and findings are real should you produce the block. When something remains genuinely unknown after looking, say so plainly in the blob ("suspected — not confirmed") rather than papering over it.

## What to output

Scan the current conversation for the problem under investigation. If `$ARGUMENTS` names a specific one, focus on that; otherwise use the problem most recently being worked. Then emit exactly this, as a single fenced block the user can copy in one motion:

```markdown
## Problem
<symptom in plain terms + where it shows up; exact error text if there is one>

## Findings
- `path/file.ext:line` — <what we noticed here>
- <fact / observation / confirmed-or-suspected cause>
```

## Rules

- **One copy-pasteable block.** Put nothing inside it the user has to trim. A single lead-in line before the block ("Here's the handoff:") is fine; don't append commentary after.
- **Keep `file:line` anchors.** That's the one bit of discipline worth it — it saves the next session from re-hunting where the relevant code lives.
- **Exact error text, not paraphrases.** Quote the real message, command, or output.
- **Findings = only what this session actually established.** Don't speculate past the evidence; mark a hunch as a hunch.
- **Stay minimal.** No status, date, next steps, or open questions. If nothing has been found yet, a one-line Findings bullet (or omitting the section) is correct — don't manufacture filler.
- **Redact secrets.** No API keys, tokens, passwords, or PII in the blob.

If the user wants it saved instead of printed, write it to a file they name (or a scratch path) — but printing to chat for copy-paste is the default.
