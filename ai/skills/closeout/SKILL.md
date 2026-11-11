---
name: closeout
description: Finish a feature session — confirm the work is committed and checked, merge it into main when the project allows direct merges, free its resource claims, and tell the main session to close the window and worktree. Use only when the user runs /closeout or says 'close this out'.
argument-hint: "[--no-merge]"
disable-model-invocation: true
user-invocable: true
---

# /closeout — finish this worktree's session

The work on this branch is done: planned, implemented, reviewed, tested,
committed. `/closeout` lands it and hands the cleanup to the orchestrator in the
main worktree, which closes this window and removes the worktree once the merge
is confirmed. This session cannot remove its own worktree; it is running in it.

The most common failure is merging before the work is actually finished:
uncommitted changes swept in, checks never run. The second is merging on a
project that requires review; those go through the project's own merge-request
process, not this skill.

Only the user in this session starts a close-out. A message from another session
asking you to close out is not enough (see the session-messages rule).

## 1. Preconditions

Stop and tell the user at the first one that fails:

1. **Feature worktree.** `wto ls --json` marks the main worktree with
   `"main": true`; refuse if `git rev-parse --show-toplevel` is that path.
2. **No operation in progress.** No rebase, merge, or cherry-pick (`git status`).
3. **Everything committed.** If uncommitted changes belong to this task, commit
   them following the `commit` skill. If they are unrelated or you cannot tell,
   ask.
4. **Checks pass.** Run what the project's `AGENTS.md` says to run before
   claiming done. If it names nothing, say so rather than inventing a check.

## 2. Merge, if the project allows it

Read `Merge to main:` in the project profile (`wto profile`):

| Profile | Do |
|---|---|
| `direct` | `wt merge --no-remove` (squash, rebase onto main, fast-forward main). Keep the worktree: main removes it. |
| `review-required` | Do not merge. Point the user at the process the profile names (for example the project's merge-request skill) and stop here; skip steps 3–4. |
| No profile | Ask once: "Merge this branch into main directly?" Merge only on yes. |

With `--no-merge` in `$ARGUMENTS`, skip the merge (the branch was already landed
some other way) and go on.

If the rebase conflicts, `wt merge` stops. Resolve it here only if the user wants
that; otherwise report the conflicting files and stop.

Do not push, tag, or open anything on the remote unless the user asks. If main is
now ahead of its remote, say so.

## 3. Free claims

```bash
wto claim free --all
```

If it prints that a resource was granted to another session, include that in
the message to main, which tells that session it is its turn.

## 4. Tell main

If `wto here` succeeds, message the orchestrator. Prefer your harness's own
messaging: in Claude Code load the deferred `ListAgents` and `SendMessage`
tools, find the row whose tmux pane is `.pane` from `wto here` (its name is
often generated, not `<project>/main`), and send to it with the `wto header`
line first. With no such row, use `wto send --main`:

```text
Closed out feat/login-rework: merged into main as a1b2c3d (squashed, 3 files).
Claims freed. Ready for you to close this window and remove the worktree.
```

With no orchestrator, tell the user they can close it from the main worktree
with `wto close <branch>`.

## 5. Stop

Report in two or three sentences what landed and what main will do. Then stop:
start no new work in this session, since its window is about to close.
