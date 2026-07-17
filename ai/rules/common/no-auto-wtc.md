# Worktrunk agent sessions are user-triggered only

`wtc` / `wta` / `wtaa` open a real worktree + tmux AI window. **Never run them
unless the user explicitly asked this turn** (ran `/wtc`, said "wtc that",
"spawn a fix agent", "open a worktree for this", etc.).

**Do suggest.** If you find a secondary bug, follow-up feature, or other work
worth a parallel agent, offer a ready-to-run line the user can paste or invoke:

```text
/wtc fix/<short-slug> <one-line task + file:line or error anchors>
```

Keep the suggestion brief — one line is ideal. Do not execute it, and do not
nudge repeatedly if they ignore it. The user may also run `/wtc` (or shell
`wtc`) themselves at any time with no suggestion from you.
