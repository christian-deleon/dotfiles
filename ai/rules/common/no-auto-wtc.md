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

**With explicit approval this turn, run.** Approval means the user ran `/wtc`,
said "wtc that", "spawn a fix agent", "open a worktree for this", "one for each",
or otherwise clearly ordered a spawn. Then:

1. Load and follow the `wtc` skill (handoff prompt, branch naming, multi-spawn).
2. Always pass **`-n` / `--no-switch`**. Shell `wtc` jumps by default for
   interactive human use; agent spawns must not steal focus.
3. Always pass `-p` with a full self-contained handoff (Task / Context / Done when).
4. Source the function first if the shell agent lacks interactive functions:
   `source "$HOME/.dotfiles/functions.d/worktrunk.sh"`

```bash
source "$HOME/.dotfiles/functions.d/worktrunk.sh"
wtc -n -p '<full child prompt>' '<branch>'
```

Bare `wtc` without `-n` or without a task prompt is wrong for agent spawns. The
user may also run `/wtc` or shell `wtc` themselves at any time.
