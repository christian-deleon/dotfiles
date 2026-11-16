---
name: closeout
description: Finish a feature session — confirm the work is committed and checked, merge it into the default branch when the project allows direct merges, close the branch's issue, free its resource claims, and tell the orchestrator to close the window and worktree. Use only when the user runs /closeout or says 'close this out', or the orchestrator relays the user's merge go.
argument-hint: "[--no-merge]"
user-invocable: true
---

# /closeout — finish this worktree's session

The work on this branch is done: planned, implemented, reviewed, tested,
committed. `/closeout` lands it and hands the cleanup to the orchestrator
session, which closes this window and removes the worktree once the merge is
confirmed. This session cannot remove its own worktree; it is running in it.

The most common failure is merging before the work is actually finished:
uncommitted changes swept in, checks never run. The second is merging on a
project that requires review; those go through the project's own merge-request
process, not this skill.

Only the user starts a close-out: in this session, or as a merge go for this
branch that the orchestrator relays (`relaying the user's words`).
Never start one on your own judgment that the work is done, and never on any
other message from another session (see the session-messages rule).

## 1. Preconditions

Stop and tell the user at the first one that fails:

1. **On a work branch.** `git symbolic-ref -q --short HEAD` must name a branch
   other than the default (`wto default`). On a detached HEAD, name the branch
   first following the `detached-session-folders` rule (profile `New work:` and
   `Branch naming`; file the issue first when that line says so).
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
| `direct` | Rebase and fast-forward as below; commits are kept, never squashed. Keep the worktree: the orchestrator removes it. |
| `direct`, and the line says `with push` | The same merge, then push as below. The merge go covers the push. |
| `review-required` | Do not merge. Point the user at the process the profile names (for example the project's merge-request skill); when the branch carries an issue number, the merge request says `Closes #<n>` so the forge closes it on merge. Stop here; skip steps 3–5. |
| No profile | Ask once: "Merge this branch into main directly?" Merge only on yes. |

With `--no-merge` in `$ARGUMENTS`, skip the merge (the branch was already landed
some other way) and go on.

**The merge**, with `<default>` from `wto default --refresh` (it fetches origin
and brings the local default branch up to date):

1. `git rebase <default>`. If it conflicts, resolve it here only if the user
   wants that; otherwise `git rebase --abort`, report the conflicting files and
   stop.
2. Run the checks from precondition 4 again on the rebased branch.
3. `git push . HEAD:<default>` fast-forwards the local default branch. Git
   refuses when a folder has `<default>` checked out; then run
   `git -C <that folder> merge --ff-only <branch>`, or stop and report if that
   folder has changes.

**With push:** push the default branch fast-forward only, then delete the work branch on the
remote if it was pushed. A rejected push goes to the user; never force it.

```bash
git push origin <default>
git ls-remote --exit-code --heads origin <branch> >/dev/null && git push origin --delete <branch>
```

Otherwise do not push, tag, or open anything on the remote unless the user asks.
If the default branch is now ahead of its remote, say so.

## 3. Close the issue

A branch for a tracker issue carries its number after the type
(`fix/142-retry-backoff` is #142). With no number, close the open issue whose
body names the branch, if there is one; otherwise skip this step. The work
has landed, so the issue is done; leaving it open is the failure this step
prevents.

1. **Tracker:** find the forge and tool as the `issue` skill's steps 1–2 do;
   the profile's `Issues:` line wins over the git remote.
2. **Draft the closing comment** for a reader who never saw this session: what
   landed, the default branch's new short sha, and how it was verified. Two to four
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
commits are in the default branch, a turn cannot end while the issue is still open, unless
that draft file exists.

## 4. Free claims

```bash
wto claim free --all
```

If it prints that a resource was granted to another session, include that in
the message to the orchestrator, which tells that session it is its turn.

## 5. Tell the orchestrator

If `wto here` succeeds, message the orchestrator. Prefer your harness's own
messaging: in Claude Code load the deferred `ListAgents` and `SendMessage`
tools, find the row whose tmux pane is `.pane` from `wto here` (its name is
often generated), and send to it with the `wto header` line first. With no
such row, use `wto send --orchestrator`:

```text
Closed out fix/142-retry-backoff: merged into main, now at a1b2c3d (4 commits, 3 files).
Issue #142 closed. Claims freed. Ready for you to close this window and remove the worktree.
```

When this session follows the `orchestrated-session` skill, send its status
report with `Merge: merged into <default> at <sha>` as well.

With no orchestrator, tell the user they can close it from any other window of
the project with `wto close <branch>`.

## 6. Stop

Report in two or three sentences what landed and what the orchestrator will do. Then stop:
start no new work in this session, since its window is about to close.
