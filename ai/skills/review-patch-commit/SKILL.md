---
name: review-patch-commit
description: >-
  Review local uncommitted changes, implement every finding, then commit.
  Use when the user runs /review-patch-commit, or says review then fix then
  commit, apply the review and commit, or wrap up with a review. Not for
  review-only or commit-only.
compatibility: opencode
argument-hint: "[--no-verify]"
disable-model-invocation: true
when-to-use: >-
  Use when the user wants a review of current work, the findings implemented,
  and the result committed in one run.
---

# Review, patch, commit

One run: review the local working tree, implement every open finding, then
commit. This is the wrap-up pipeline for work already in the tree — not a
feature builder (`/implement`) and not a review-only pass (`/review`).

Invoking this skill **is** the explicit ask to commit. Do not re-ask.

The most common failure mode is stopping after the review (treating this as
`/review`) or asking "should I implement / commit?" at the end. Finish the
pipeline unless a phase fails.

## Arguments

| Argument | Effect |
|---|---|
| `--no-verify` | Passed through to the `commit` skill. Same natural-language aliases as that skill (`no-verify`, `skip verify`, `in a hurry`, …). |
| anything else | Reject and stop. This skill only reviews **local uncommitted changes**. For a PR or named branch, use `/review`. |

## Pipeline

Do not copy the `review` or `commit` skill bodies into this file. Read each
and follow it.

### 1. Review

Read and follow the `review` skill in **local mode** (as if the user ran
`/review --local`).

The `review` skill's read-only rule applies **only during this phase**. After
the reviewer finishes and the review file is on disk, that constraint ends.

If the working tree is clean (review empty-diff exit): tell the user and
**stop**. Nothing to patch or commit.

Keep the path to `<review_file>`. Phase 2 needs it.

### 2. Patch

If the review has **zero** issues: skip to phase 3.

Otherwise **you** implement the findings. Do not spawn an implementer
subagent — this is not `/implement`. Read `<review_file>` and handle every
issue with `Status: open`, bugs first, then suggestions, then nits.

For each issue:

- **Executable logic** — load and follow the `test-driven-development` skill
  (red test from an independent expected value, then the fix).
- **Non-logic** (copy, comments, formatting, wiring with no control-flow
  change) — smallest edit; no test.
- **Disagree** — set `Status: wontfix` with a technical reason. Do not
  implement a finding that would make the code worse.
- **Already true in the tree** — set `Status: fixed` and note that; do not
  churn.

After each issue, update that block in `<review_file>`: `Status: fixed` or
`wontfix`, plus a `Response:` line.

Smallest change that addresses the finding. Match existing patterns. No extra
features. No comment slop.

Do **not** start a second review round. One review, then patch, then commit.

If a patch fails (cannot make the change, tests will not go green): **stop**.
Do not commit. Report what landed and what did not.

### 3. Commit

Read and follow the `commit` skill on the resulting tree (original work plus
patches).

Pass `--no-verify` into that skill only when the user opted out. Otherwise
the commit skill's verify-before-commit rule stands — reuse a passing run
from this conversation when it still covers the tree.

Do not push.

## Report

After commit, one short recap:

- Review: N issues (bugs / suggestions / nits)
- Patched: which issues were fixed vs wontfix (one line each)
- Commits: SHAs and subjects the commit skill created
- Path to `<review_file>` if it still exists

## Do not

- Stop after printing the review
- Ask whether to implement or commit
- Post a GitHub PENDING review (`/review --pr` is a different skill)
- Copy the `review` or `commit` workflows into this file
- Run the `/implement` review-fix loop
- Push
