# Issue templates by type

Pick the type that matches what the conversation produced, then fill only the
sections the session actually supports — drop any that would be empty or
guessed. A repo's own issue template overrides these.

| Type | Use when | Title shape |
|---|---|---|
| Bug | Something behaves wrong or fails | What's broken, where: "Sync client drops token refresh on 401" |
| Feature | New capability or a change in behavior | What it lets someone do: "Export reports as CSV" |
| Task | Work with no user-visible change: refactor, cleanup, upgrade, docs, tests | The action: "Replace hand-rolled retry loop with backoff helper" |
| Tracking | Parent issue for a split effort | The overall goal: "Migrate auth to OIDC" |

If the repo has a label for the type (`bug`, `enhancement`/`feature`, `chore`,
…), apply it. Don't create one.

## Bug

```markdown
## Context
Where this came up and why it matters.

## What happens
Observed behavior, with exact error text or output.

## Expected
What should happen instead.

## Reproduce
1. Steps or command
2. Environment details that matter (version, OS, config)

## What we know
- `path/file.ext:42` — suspected cause or relevant code
- Approaches already ruled out

## Done when
- The failing case passes; no regression in …
```

## Feature

```markdown
## Context
Where the need came up.

## Goal
What someone should be able to do, and why it's worth doing.

## Proposed approach
Only what the conversation settled. Alternatives considered and why they lost.

## Open questions
Decisions still to make — don't resolve them here.

## Done when
- Observable acceptance criteria

## Out of scope
- Boundaries the conversation drew
```

## Task

```markdown
## Context
Why this work is needed now (or was deferred).

## Work
What changes, at the level of files, components, or steps.

## Notes
- `path/file.ext:42` — relevant code, constraints, gotchas found

## Done when
- Concrete finish line (old path removed, tests green, docs updated…)
```

## Tracking (parent of a split)

```markdown
## Goal
The overall outcome and why.

## Pieces
- [ ] #12 Short title — one line on what it covers
- [ ] #13 Short title — depends on #12

## Open questions
Things the conversation didn't settle that affect the split.

## Done when
- All pieces closed, plus any end-to-end check
```

Each child of a tracking issue uses the Bug, Feature, or Task template and
adds `Part of #<parent>` at the top.
