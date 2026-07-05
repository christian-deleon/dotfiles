# Prove a bug before you fix it

When fixing a reported or discovered bug, don't jump straight to the fix. Write
a test that reproduces it first — otherwise you can't tell whether your test
actually exercises the bug or just passes vacuously against your own fix.

The most common AI failure mode here: writing (or updating) a test against the
code you just wrote, so the test silently encodes the same bug the code has
and can never catch it. This is tautological testing — the fix is to derive
the test's expected value from an independent source of truth (the bug
report, a spec, a known-good literal, a worked example) and never recompute it
the way the implementation computes it.

Sequence, in order:
1. Write a test asserting the correct behavior, using an expected value from
   an independent source of truth — not derived from the current
   implementation.
2. Run it and confirm it fails for the expected reason (the same symptom as
   the bug), not for an unrelated reason like a typo or import error. Skipping
   this step is the single easiest way to end up with a test that never
   actually exercised the bug.
3. Apply the minimal fix.
4. Re-run the same test and confirm it now passes.
5. Run the full suite to catch regressions.
6. Keep the test — it's the permanent guard against this bug recurring.

Never write a "fix" and its test in the same pass without running step 2 in
between. If you can't run the test suite in the current environment, say so
explicitly rather than reporting the bug as fixed.

## When the project has no tests

This rule applies to projects that already have a test suite. If the project
has no tests, do NOT introduce a test framework, test directory, or test
dependencies just to satisfy this rule — an untested project may be untested
on purpose, and project-level instructions saying "no tests" always win.

The underlying discipline still applies, just without test files: reproduce
the bug manually first (run the command, script, or repro steps and observe
the wrong behavior yourself), apply the fix, then repeat the same steps and
confirm the behavior is now correct. Prove-fail-then-prove-pass, with a shell
session standing in for the test runner. If you genuinely think the project
would benefit from a test suite, ask — never scaffold one uninvited.
