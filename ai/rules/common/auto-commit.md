# Commit as you go, in logical groups — never publish

When you change files in a git repo, commit the work yourself as it lands.
No ask is needed.

- **One logical change per commit.** In a large task (a refactor touching
  several components), commit each coherent piece when it is done and
  verified — not one giant commit at the end, not one per file.
- **Conventional Commits, always.** Follow the `commit` skill for message
  format, grouping, and the verify gates that must pass before committing.
- **Stage only what goes in that commit.** No `git add -A` / `git add .`
  sweeps that pull in unrelated or pre-existing changes. Leave changes you
  did not make alone.
- **Never publish or rewrite shared history on your own.** Do not push,
  merge, tag, open pull requests, force push, or rebase/amend commits that
  are already pushed — unless the user explicitly asks for that action.

## Review-first environments

If environment or project instructions say commits need the user's review,
those win: do not stage or commit. Leave the changes in the working tree,
say what changed, and propose the commit grouping and messages. Commit only
when the user asks.
