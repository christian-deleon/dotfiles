# No comment / documentation slop

Comments and docs exist for **information the code, types, tests, and names do
not already carry** — rationale, invariants, non-obvious constraints, rejected
alternatives, sharp edges. They are not a changelog, a tutorial of the next
lines, or a dump of "helpful" residue each turn.

## Hard rules

1. **Earn its place or delete it.** Before writing or keeping a comment, ask:
   would a senior engineer miss real information without it? If no — remove it.
   Prefer clearer names/types/structure over more prose.

2. **Never write these** (and remove them when you see them):
   - **Meta / process**: phases, steps, "added as part of…", plan breadcrumbs
   - **Migration history**: "moved from", "formerly", "renamed during…"
     (git owns that)
   - **What-restatement**: narrating the next lines or restating the identifier
     (`// increment counter` above `counter += 1`)
   - **Padding / ceremony**: IMPORTANT/NOTE hedges, restating what types already
     enforce, multi-paragraph walkthroughs of obvious APIs
   - **Clarification stacks**: appending "also…" / "update:" on stale prose —
     replace or delete the original instead

3. **Prefer delete over expand.** Stale or redundant comments are bugs. Do not
   layer new prose on top of wrong prose. Do not expand comments as a substitute
   for fixing structure.

4. **Doc comments stay dense.** Public items may need docs (purpose, invariants,
   real edge cases). Do **not** restate signatures, narrate the body, or write
   tutorials on obvious helpers. Private code: usually no doc comment unless the
   invariant is subtle.

5. **Diff hygiene.** Net-negative prose is a regression. Before finishing, scan
   the change for comment/doc expansion that fails the earn-its-place test and
   strip it. No drive-by essay rewrites outside the task — but do strip banned
   categories in files you touch.

6. **Instruction files stay short.** Agent rules (`AGENTS.md`, always-on rules)
   are actionable constraints, not essays. Bloated instruction files get ignored;
   prune lines that no longer prevent a real mistake.

## Good vs bad (one glance)

```
// BAD: Phase 2 — wire the healer
// BAD: Moved here from engine::heal
// BAD: Loop through all assets
// BAD: IMPORTANT: call after init
// GOOD: QuestDB is append-only; skip positions the synthesis pass already fixed
//       or the next heal re-synthesizes before the append is query-visible.
```

Architecture / requirements Markdown may discuss history. Source comments and
docstrings must not.
