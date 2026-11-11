# Worktrunk agent sessions need explicit approval

`wtc` / `wta` / `wtaa` open a real worktree + tmux AI window.

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
2. **Run** `wtc` in the shell tool — do not paste a `/wtc …` or shell command
   for the user to re-run. They already approved; you spawn.
3. Always pass **`-n` / `--no-switch`**. Shell `wtc` jumps by default for
   interactive human use; agent spawns must not steal focus.
4. Always pass `-p` with a full self-contained handoff (Task / Context / Done when).
5. Source the function first if the shell agent lacks interactive functions:
   `source "$HOME/.dotfiles/functions.d/worktrunk.sh"`

```bash
source "$HOME/.dotfiles/functions.d/worktrunk.sh"
wtc -n -p '<full child prompt>' '<branch>'
```

Bare `wtc` without `-n` or without a task prompt is wrong for agent spawns. The
user may also run `/wtc` or shell `wtc` themselves at any time.

**Orchestrator mode.** In a session running `/orchestrate`, the user's request to
start work, or their approval of a proposed batch, is the spawn order for exactly
those items, nothing more.

**Side work in a feature worktree.** When `wto here` succeeds (an orchestrator is
running), suggest `/spinoff <one line>` instead of a `/wtc` line; it files the
issue and hands it to main. File nothing until the user agrees.
