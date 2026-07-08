# Test-driven development — prove behavior, don't assume it

Whether you're fixing a bug or building a feature, write the test before you
trust the code, and make the test's expected value come from an independent
source of truth — the bug report, a spec, an acceptance criterion, a
known-good literal, a worked example — never recomputed the way the
implementation computes it.

The most common AI failure mode: writing the test against the code you're
about to write (or just wrote), so the test silently encodes the same
assumption the code has and can never catch a divergence from what was
actually wanted. This is tautological testing. For a bug fix it shows up as
asserting what the buggy code *does*; for a new feature it shows up as
asserting the implementation you're already planning instead of the
requirement. The fix is the same in both cases: derive the expected value
independently.

Sequence, in order:
1. Write a test asserting the *correct/desired* behavior, with the expected
   value from an independent source of truth — not derived from the current
   or planned implementation.
2. Run it and confirm it fails for the expected reason (a bug's actual
   symptom; a feature's not-yet-implemented behavior), not an unrelated error
   like a typo or missing import. This is the single easiest step to skip and
   the one that proves the test actually exercises the thing.
3. Write the minimal code to make it pass.
4. Re-run the same test and confirm it passes.
5. Run the full suite to catch regressions.
6. Keep the test — it's the permanent guard.

Never write code and its test in the same pass without running step 2 in
between. Ordering alone is not the safeguard — a test written first can still
assert the wrong thing; the independent expected value is what does the real
work. If you can't run the suite in the current environment, say so rather
than reporting the work as verified.

## When the project has no tests

Not every project has a test suite, and many are untested on purpose. Do NOT
introduce a test framework, test directory, or test dependencies just to
satisfy this rule — a project-level "no tests" instruction always wins, and
scaffolding a suite uninvited is worse than the discipline it's meant to
serve.

The underlying discipline still applies without test files: reproduce the
current behavior manually first (run the command, script, or steps and
observe the wrong or missing behavior yourself), make the change, then repeat
the same steps and confirm the behavior is now what you wanted.
Prove-fail-then-prove-pass, with a shell session standing in for the test
runner. If you think the project would genuinely benefit from tests, ask —
never add them on your own.

For the full phased workflow (the bug-vs-feature fork, quality checklists,
and escalation criteria), use the `test-driven-development` skill.
