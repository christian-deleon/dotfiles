---
name: test-driven-development
description: Test-first repair and construction. Use when fixing a bug or building a feature in a project that has (or should have) tests. Write a failing test that encodes the correct/desired behavior first, confirm it fails for the right reason, then make the minimal change to turn it green. Prevents tests that just re-encode the code's own logic. Skip for projects deliberately without tests.
compatibility: opencode
allowed-tools: Read Grep Glob Bash
---

# Test-Driven Development

Write a test that fails because the desired behavior is missing, then write
the minimal code to make it pass. The test comes first because it is the
specification — it says what "correct" looks like in machine-checkable form,
externalized *before* the implementation exists to bias it.

The most common AI failure mode this prevents: writing the test against the
code you're about to write (or just wrote), so the test encodes the same
assumption the code has and can never catch a divergence from what was
actually wanted. This is tautological testing. The safeguard is not the
ordering — a test written first can still assert the wrong thing — it is
where the expected value comes from: an **independent source of truth**, never
recomputed the way the implementation computes it.

## First: is this even the right skill?

- **If the project has no test suite and is untested on purpose**, stop — do
  not use this skill to justify scaffolding a framework, test directory, or
  test dependencies. A project-level "no tests" instruction always wins. Fall
  back to the manual discipline in the last section, or ask the user before
  adding tests.
- **Otherwise**, continue. Match the project's existing test layout, runner,
  and conventions — this skill describes the *method*, not a specific
  framework or command.

## Mode fork: bug fix vs. new feature

The engine is identical; two things differ — what "correct behavior" means
and where the expected value comes from. Decide which mode you're in first.

| | **Bug fix** | **New feature** |
|---|---|---|
| Code exists? | Yes, and it's wrong | No, or partial |
| The trap | Asserting what the buggy code *does* | Asserting the implementation you're *planning* |
| "Correct behavior" is | What *should* happen instead of the observed bug | The requirement / acceptance criteria |
| Source of truth for the expected value | The bug report, the observed-vs-expected gap, the exact error/output the reporter saw | The spec, ticket, acceptance criteria, or a worked example — decided before you design the code |
| Red means | Fails with the bug's actual symptom | Fails because the behavior isn't built yet |

If you can't state the expected value from a source *other than* the code you
are about to write, you don't yet understand the requirement — go get it
before writing the test.

## Critical rules (both modes)

1. **The test encodes desired behavior, not current or planned behavior.**
   Assert what *should* happen. For a bug, resist describing what the code
   does today. For a feature, resist describing the implementation you have
   in your head.
2. **Never edit the test to match the code during the green phase.** The test
   is the spec; the code conforms to it, not the reverse. If you become
   convinced the test itself is wrong, STOP and discuss it as a separate
   step before resuming.
3. **Never skip the red state.** If you cannot produce a failing test, you do
   not yet understand the bug or the requirement. Go back and research —
   read the code, trace the path, clarify the spec. Do not proceed to
   implementation without a test that fails for the right reason.
4. **Minimal change only.** Write the smallest code that turns the test
   green. If it requires broad or cross-cutting changes, pause and plan with
   the user first.
5. **Run the test after every edit.** One change, run, observe — don't batch
   edits and hope.

## Process

### Phase 1 — Understand

Before writing anything:

- **Bug:** identify what currently happens, what should happen, and the
  conditions that trigger it (inputs, state, timing). Form a hypothesis about
  *why* the code is wrong, not just *that* it is — so the test targets the
  root cause, not a symptom.
- **Feature:** identify the observable behavior the feature must exhibit and
  its acceptance criteria. Pin down concrete expected outputs for concrete
  inputs *from the requirement*, before thinking about implementation.

For anything non-trivial, delegate the code-path tracing to a subagent so you
spend your own context on the judgment, not the search. If you cannot form a
clear hypothesis (bug) or a concrete expected behavior (feature), tell the
user what you found and ask — do not guess.

### Phase 2 — Write the failing test (Red)

Write a test that fails *today* for the right reason.

- Put it where the project's existing tests of that kind live; match their
  structure and naming.
- Name the test after the correct behavior, not the bug.
- Use realistic inputs that actually exercise the behavior, and an expected
  value taken from the source of truth for your mode (see the fork table).
- Keep it minimal — one specific behavior, not a broad scenario. It should
  remain valuable afterward as a permanent regression/spec test.

Failure modes to avoid:
- Asserting the current (buggy) or planned value — passes immediately and is
  worthless.
- Testing a symptom instead of the root cause — may pass after a superficial
  fix that doesn't address the real problem.
- Over-specifying implementation details — makes the test brittle. Assert
  observable behavior.

### Phase 3 — Confirm the red state

Run *just the new test* and verify it fails. **It must fail**, and **for the
right reason** — read the failure output and confirm the gap it shows is the
one you intended (the bug's symptom, or the missing feature behavior). If it
fails on a typo, missing import, or setup/type error, fix the test
infrastructure, not the assertion.

If it *passes* unexpectedly, one of these is true: the test doesn't exercise
the behavior; it asserts current/planned behavior instead of desired; or your
model of where the behavior lives is wrong — go back to Phase 1.

Once it fails for the right reason: **freeze the test.** Do not touch it again
until the implementation is complete.

### Phase 4 — Implement (Green)

Make the minimal change that turns the frozen test green. One targeted edit,
run the test, read the result, adjust, repeat until it passes. During this
phase: do not edit the test, and do not make unrelated changes (refactors and
cleanup are separate work).

If you feel the urge to change the test, ask yourself: "Am I making the code
match the test, or making the test match the code?" Only the first is
allowed.

### Phase 5 — Verify no regressions

Run the full relevant test suite (and the project's lint/format/type checks
if it has them). The new test *and* every existing test must pass together.

If existing tests fail after the change:
- They may have been asserting the old/buggy behavior — if so they need
  correcting, but discuss with the user before changing them.
- Or the change is too broad and has side effects — narrow it.

### Phase 6 — Report

Tell the user: the root cause (bug) or the behavior added (feature); what the
new test checks and why it failed before; what changed and why it's the right
change; and confirmation that the full suite passes. The test is now a
permanent guard.

## When the project has no tests

If there is no suite and one isn't wanted, the method still holds without test
files: reproduce the current behavior manually (run the command, script, or
steps and observe the wrong or missing behavior yourself), make the change,
then repeat the exact same steps and confirm the behavior is now what you
wanted. Prove-fail-then-prove-pass with a shell session as the test runner.
Never introduce a test framework to satisfy this skill; if you think the
project would benefit from tests, ask first.

## When to stop and escalate

Pause and consult the user if:
- You cannot write a test that fails (you don't understand the bug or the
  requirement).
- The minimal change requires broad, cross-module, or public-API changes.
- Existing tests fail after the change and you're unsure whether they're wrong.
- You realize the "bug" might be intended behavior, or the "feature" conflicts
  with existing behavior.
