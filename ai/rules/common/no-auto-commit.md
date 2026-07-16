# Never auto-commit — wait for an explicit ask

Do not run `git commit`, `git push`, `git tag`, or open pull requests unless
the user explicitly asks (e.g. "commit this", `/commit`). Do not stage changes
unless explicitly asked.

When a task is done, state what changed. Offering a commit or next-step options
is fine; acting on them is not, until the user says so.
