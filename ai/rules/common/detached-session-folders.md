# Detached session folders: name the work when it is clear

A folder from `wtc` starts on a detached HEAD at the latest default branch.
Its codename never changes; the branch you name later is what the work is
called. Naming it is not a commit, so it can happen as soon as the work is
clear, in a conversation that has produced nothing to commit yet.

This applies only in a linked worktree on a detached HEAD with no rebase or
bisect running.

## How this project starts new work

Read the `New work:` line of the project profile (`wto profile`; exit 1 means
there is none).

| Line | Do |
|---|---|
| `issue and branch` | Once the work is clear, file the issue with the `issue` skill, then create the branch with its number. No ask. |
| `branch` | Once the work is clear, create the local branch. File no issue. No ask. |
| `on request`, no line, or no profile | Offer a branch name once, when the work is clear. Create it only when the user agrees. |

The line is the user's standing go for that project. It does not skip the
`issue` skill's own rules (duplicates, `Issue drafts:`).

An explicit request for an issue or a branch is always honored at once,
whatever the line says. So is an explicit request to commit, push, or open a
merge request — `/publish`, or the same ask in words. That ask
is the agreement to create the branch. Name it and create it, then continue.
Do not offer the name and wait, even when the line is `on request`, there is
no line, or there is no profile.

## Creating the branch

- Name it by the profile's `Branch naming`, with the issue number right after
  the type when there is one (`fix/142-retry-backoff`).
- If the session referenced a Jira issue key, put that key in the same place
  (`feat/NGC-9795-container-release-manifest`). Use the key this work is for,
  not every key that came up. Do not invent one.
- `git switch -c <name>` in place, then carry on with the session. The branch
  stays local: push or set an upstream only as `auto-commit.md` allows.
- Never rename a branch that is already pushed.
