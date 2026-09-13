# AGENTS.md and README are different files

Do not copy one into the other. They have different readers and different
jobs. The usual failure on a new project is writing `AGENTS.md` and
`README.md` as the same document twice.

| File | Reader | Job |
|------|--------|-----|
| `README.md` | Humans (GitHub, onboarding, you in six months) | What this is, why it exists, how to install / run / use it |
| `AGENTS.md` | Coding agents | Constraints that change agent behavior: conventions, gotchas, verify commands, what not to do |

## Keep them from collapsing

- **One home per fact.** Product pitch, feature list, and getting-started
  live in the README. Agent constraints live in `AGENTS.md`. If a fact is
  already in one, the other gets a pointer — not a restatement.
- **`AGENTS.md` is not a second README.** No architecture essay, no
  tutorial, no feature catalog. Short, actionable, easy to ignore if
  bloated (see `no-comment-slop.md`).
- **README is not agent policy.** Don't dump "never commit `.env`" or
  skill pointers there unless a human actually needs them to use the repo.
- **Don't create `AGENTS.md` just to have one.** Write it when there are
  real agent constraints. Don't create a README that is only a paste of
  the agent file.

Shared items (how to run tests, how to build) still differ by audience:
README explains it for a person; `AGENTS.md` states the check the agent
must run before claiming done — not a second walkthrough.
