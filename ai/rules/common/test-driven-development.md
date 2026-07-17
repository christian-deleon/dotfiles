# Test-driven development — prove behavior, don't assume it

Write the test before you trust the code. Derive the expected value from an
independent source of truth (bug report, spec, acceptance criterion, known-good
literal) — never recompute it the way the implementation does.

The most common failure: tautological tests that encode the same assumption as
the code (asserting what buggy code *does*, or the implementation you're already
planning). Independent expected values prevent that.

## Sequence (blocking — do not skip)

1. Write a test for the *desired* behavior with an independent expected value.
2. Run it; confirm it fails for the right reason. **Record the command and
   failure summary before any production-code edit.**
3. Write the minimal code to pass.
4. Re-run the same test; confirm pass.
5. Run the full suite for regressions.
6. Keep the test. When reporting, include the red evidence from step 2.

Never write production code and its test in the same pass without step 2
between them. If you can't run the suite, say so — don't claim verification.

## When the project has no tests

Do **not** scaffold a test framework uninvited. A project-level "no tests"
instruction always wins. Reproduce manually (prove fail → change → prove pass);
ask before adding tests.

For the full phased workflow (bug-vs-feature fork, checklists, escalation), use
the `test-driven-development` skill.
