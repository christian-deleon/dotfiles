# Worktrunk agent sessions are user-triggered only

`wtc` / `wta` / `wtaa` open a real worktree + tmux AI window. **Never run them
unless the user explicitly asked this turn** (ran `/wtc`, said "wtc that",
"spawn a fix agent", "open a worktree for this", etc.).

**Do suggest.** If you find secondary bugs, features, or other work worth a
parallel agent, offer ready-to-run line(s) the user can paste or invoke:

```text
/wtc fix/<short-slug> <one-line task + file:line or error anchors>
```

For several items, list one `/wtc …` per item, or a single multi-trigger like
`/wtc one for each of the N above`. Keep it brief. Do not execute, and do not
nudge repeatedly if they ignore it. The user may also run `/wtc` (or shell
`wtc`) themselves at any time — with a message, empty (use chat context), or
"one for each" — with no suggestion from you.
