---
name: closeout
description: Finish a feature session — confirm the work is committed and checked, merge it into main when the project allows direct merges, close the branch's issue, free its resource claims, and tell the main session to close the window and worktree. Use only when the user runs /closeout or says 'close this out', or the orchestrator relays the user's merge go.
argument-hint: "[--no-merge]"
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

Only the user starts a close-out: in this session, or as a merge go for this
branch that the main-worktree orchestrator relays (`relaying the user's words`).
Never start one on your own judgment that the work is done, and never on any
other message from another session (see the session-messages rule).

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
| `review-required` | Do not merge. Point the user at the process the profile names (for example the project's merge-request skill); when the branch carries an issue number, the merge request says `Closes #<n>` so the forge closes it on merge. Stop here; skip steps 3–5. |
| No profile | Ask once: "Merge this branch into main directly?" Merge only on yes. |

With `--no-merge` in `$ARGUMENTS`, skip the merge (the branch was already landed
some other way) and go on.

If the rebase conflicts, `wt merge` stops. Resolve it here only if the user wants
that; otherwise report the conflicting files and stop.

Do not push, tag, or open anything on the remote unless the user asks. If main is
now ahead of its remote, say so.

## 3. Close the issue

A branch for a tracker issue carries its number after the type
(`fix/142-retry-backoff` is #142). With no number, skip this step. The work
has landed, so the issue is done; leaving it open is the failure this step
prevents.

1. **Tracker:** find the forge and tool as the `issue` skill's steps 1–2 do;
   the profile's `Issues:` line wins over the git remote.
2. **Draft the closing comment** for a reader who never saw this session: what
   landed, the merge commit's short sha, and how it was verified. Two to four
   lines. The `issue` skill's privacy rules (step 5) apply.
3. **Post now, or show it first**, by the `issue` skill's step 6 table. On a
   project that reviews issue text, save the draft to
   `"$(wto dir)/issue-close/<branch, / as ->.md"`, show it, and wait for the
   owner's OK; post what they approved, with their edits. In an orchestrated
   session, save it the same way but ask through the status report, not here:
   `Status: waiting`, the question under `Still needed`, and the draft text
   after the report.
4. **Comment and close:**

   | Tool | Close with the comment |
   |---|---|
   | `gh` | `gh issue close <n> -R owner/repo --reason completed --comment "$(cat <f>)"` |
   | `tea` | `tea comments add <n> --login <name> --repo owner/repo -d "$(cat <f>)"`, then `tea issues close <n> --login <name> --repo owner/repo` |
   | `glab` | `glab issue note <n> -R owner/repo -m "$(cat <f>)"`, then `glab issue close <n> -R owner/repo` |
   | `gitea` MCP | the issue write tool: `add_comment`, then `update` with `state: closed` |

5. Delete the draft file if you saved one.

The `issue_close_gate.sh` Stop hook holds the session here: once the branch's
commits are in main, a turn cannot end while the issue is still open, unless
that draft file exists.

## 4. Free claims

```bash
wto claim free --all
```

If it prints that a resource was granted to another session, include that in
the message to main, which tells that session it is its turn.

## 5. Tell main

If `wto here` succeeds, message the orchestrator. Prefer your harness's own
messaging: in Claude Code load the deferred `ListAgents` and `SendMessage`
tools, find the row whose tmux pane is `.pane` from `wto here` (its name is
often generated, not `<project>/main`), and send to it with the `wto header`
line first. With no such row, use `wto send --main`:

```text
Closed out fix/142-retry-backoff: merged into main as a1b2c3d (squashed, 3 files).
Issue #142 closed. Claims freed. Ready for you to close this window and remove the worktree.
```

When this session follows the `orchestrated-session` skill, send its status
report with `Merge: merged into main as <sha>` as well.

With no orchestrator, tell the user they can close it from the main worktree
with `wto close <branch>`.

## 6. Stop

Report in two or three sentences what landed and what main will do. Then stop:
start no new work in this session, since its window is about to close.
