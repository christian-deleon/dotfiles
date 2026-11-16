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
whatever the line says.

## Creating the branch

- Name it by the profile's `Branch naming`, with the issue number right after
  the type when there is one (`fix/142-retry-backoff`).
- `git switch -c <name>` in place, then carry on with the session. Do not
  push or set an upstream.
- Never rename a branch that is already pushed.
