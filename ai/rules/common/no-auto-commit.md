# Never auto-commit or auto-stage — wait for an explicit ask

Do not run `git commit`, `git push`, `git tag`, or open pull requests unless
the user explicitly asks (e.g. "commit this", `/commit`).

**Do not stage changes unless the user explicitly asks** (e.g. "stage this",
"stage and commit", or a commit request that implies staging as part of that
workflow). The working tree is the user's review surface — leave edits
unstaged so they can inspect and stage what they want.

## Anti-patterns (do not)

- `git add -A`, `git add .`, `git add -u`, or bulk `git add` "to clean up" or
  "for a nicer status"
- Staging just to run `git diff --cached` / get a staged-only diffstat —
  use unstaged `git status`, `git diff`, and `git diff --stat` instead
- Staging mid-task "so nothing is lost" — disk already has the files
- Staging after finishing work as a courtesy before offering a commit

## When staging is allowed

Only after an explicit stage or commit ask. Then stage **only** the files for
that logical unit (the commit skill forbids `git add -A` without grouping).
If you staged by mistake, unstage immediately (`git restore --staged …`) and
say so.

When a task is done, state what changed. Offering a commit or next-step options
is fine; acting on them is not, until the user says so.
