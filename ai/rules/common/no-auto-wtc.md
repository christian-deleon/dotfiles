# Worktrunk agent sessions need explicit approval

`wto new` / `wto open` (the user's `wtc` / `wta` / `wtaa`) open a real worktree +
tmux AI window.

**Never run them unprompted.** Finding secondary bugs, features, or side work is
not authorization. Suggest only:

```text
/wtc fix/<short-slug> <one-line task + file:line or error anchors>
```

For several items, list one `/wtc …` per item, or a single multi-trigger like
`/wtc one for each of the N above`. Keep it brief. Do not nudge repeatedly if
they ignore it.

**With explicit approval this turn, execute yourself.** Approval means the user
ran `/wtc`, said "wtc that", "spawn a fix agent", "open a worktree for this",
"one for each", or otherwise clearly ordered a spawn. Then:

1. Load and follow the `wtc` skill (handoff prompt, branch naming, multi-spawn).
2. **Run** `wto new` in the shell tool — do not paste a `/wtc …` or shell command
   for the user to re-run. They already approved; you spawn.
3. Pass a full self-contained handoff (Task / Context / Done when) with `-f`, and
   the job the skill picks. Never pass `--switch`; agent spawns must
   not steal focus.

```bash
wto new -j implement -f "$handoff" '<branch>'
```

The user may also run `/wtc` or shell `wtc` themselves at any time.

**Orchestrator mode.** In a session running `/orchestrate`, the user's request to
start work, or their approval of a proposed batch, is the spawn order for exactly
those items, nothing more.

**Side work in a feature worktree.** When `wto here` succeeds (an orchestrator is
running), suggest `/spinoff <one line>` instead of a `/wtc` line; it files the
issue and hands it to main. File nothing until the user agrees.
