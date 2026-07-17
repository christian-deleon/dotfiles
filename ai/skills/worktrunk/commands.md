## Commands

### `wt switch [BRANCH] [-x CMD] [-- ARGS]`

Switch to (or create) a worktree.

| Flag | Purpose |
|---|---|
| `-c`, `--create` | Create the branch from `--base` |
| `-b`, `--base <BR>` | Source branch for `--create`; defaults to default branch |
| `-x`, `--execute <CMD>` | After switching, replace `wt` with `CMD` (full terminal control) |
| `--no-cd` | Don't `cd` after switching; hooks still run |
| `--clobber` | Remove a stale non-worktree directory at the target path |
| `--branches` / `--remotes` | Picker includes branches without worktrees / remote-only branches |
| `--no-hooks` | Skip all hooks |
| `--format json` | Structured output for tool integration |

Tokens after `--` append to the `--execute` command. `-x` supports template vars (`{{ branch }}`, `{{ worktree_path }}`, `{{ base }}`, `{{ base_worktree_path }}`).

No branch arg → interactive picker (Unix only): live preview tabs (HEAD diff, log, main…±, remote, LLM summary), `Alt-c` to create, `1–5` switches preview tab, `Alt-p` toggles preview.

```bash
wt switch feat                              # existing
wt switch -c hotfix --base=production       # new branch from prod
wt switch -c fix --base=@                   # branch from current HEAD
wt switch pr:123                            # PR checkout
wt switch -x claude -c feat -- 'task text'  # parallel-agent pattern
wt switch -                                 # toggle previous
```

### `wt list`

Worktree status with rich columns. Streams fast info first, fills slow columns as background tasks complete.

| Flag | Effect |
|---|---|
| `--full` | Adds CI status, line diffs since merge-base, LLM summaries (network) |
| `--branches` / `--remotes` | Include branches without worktrees / remote-only |
| `--format json` | Machine-readable; rich field set (see below) |
| `--progressive` | Stream updates (auto-on for TTY) |

Status symbols (subset): `+` staged, `!` modified, `?` untracked, `↑/↓` ahead/behind default, `↕` diverged, `⇡/⇣/⇅` remote ahead/behind/diverged, `_` same as default, `⊂` integrated, `^` is default, `⊞` locked, `⊟` prunable, `✘` conflicts, `⤴/⤵` rebase/merge in progress.

CI dots: green (passed), blue (running), red (failed), yellow (conflicts), gray (no CI), `⚠` (fetch error). Cached 30–60s; clickable links.

JSON for scripts — every relation is a structured field, not a glyph:

```bash
# Branches with content not yet in default — i.e. needs merging
wt list --format=json | jq '.[] | select(.main.ahead > 0) | .branch'
# Integrated branches safe to remove
wt list --format=json | jq '.[] | select(.main_state == "integrated") | .branch'
# Current worktree path
wt list --format=json | jq -r '.[] | select(.is_current) | .path'
```

### `wt remove [BRANCHES]...`

Removes the worktree and (if integrated) deletes the branch. Defaults to the current worktree.

Six checks decide branch deletion safety: same-commit / ancestor / no-added-changes / trees-match / merge-adds-nothing / patch-id-match. If any pass, the branch is deletable; otherwise it's preserved unless `-D`.

| Flag | Purpose |
|---|---|
| `-f`, `--force` | Override "untracked files present" check |
| `-D`, `--force-delete` | Force-delete branch with unmerged commits |
| `--no-delete-branch` | Keep the branch even if integrated |
| `--foreground` | Run synchronously (default is background — instant rename to `.git/wt/trash/`) |
| `--no-hooks` | Skip pre/post-remove hooks |

Locked worktrees (`git worktree lock`) survive even `--force`. Use `git worktree lock --reason "…"` for worktrees that hold precious ignored data.

### `wt merge [TARGET]`

The full pipeline, GitHub-merge-button semantics: merges **current branch into target** (target defaults to default branch).

Order: `pre-commit` → commit → `post-commit` → squash → rebase → `pre-merge` → merge (fast-forward) → `pre-remove` → remove worktree+branch → `post-remove` & `post-merge`. `pre-*` are blocking; `post-*` run in background.

| Flag | Effect |
|---|---|
| `--no-squash` | Preserve individual commits |
| `--no-commit` | Skip commit+squash; requires clean tree |
| `--no-rebase` | Skip rebase (must already be rebased) |
| `--no-remove` | Keep the worktree |
| `--no-ff` | Create a merge commit (semi-linear) |
| `--stage all\|tracked\|none` | What to stage during commit/squash |
| `--no-hooks` | Skip all hooks |

Conflicts during rebase abort immediately. Non-fast-forward merges are rejected unless `--no-ff`.

### `wt step <SUBCOMMAND>`

Building blocks of `wt merge` plus standalone utilities. Useful when you want partial control.

| Step | Purpose |
|---|---|
| `commit` | Stage + commit with LLM-generated message; `--stage all\|tracked\|none`, `--dry-run` |
| `squash [TARGET]` | Squash all commits since target into one with LLM-generated message |
| `rebase` | Rebase onto target |
| `push` | Fast-forward target to current branch |
| `diff [TARGET] [-- ARGS]` | All changes since branching (committed + staged + unstaged + untracked) as one diff; pipe to `delta` |
| `copy-ignored` | Copy gitignored files between worktrees (build caches, deps); reflinks when possible |
| `eval '<TEMPLATE>'` | Evaluate a template expression and print result (use in scripts) |
| `for-each -- CMD ARGS` | Run a command in every worktree, sequentially, real-time output, continues on failure |
| `promote [BRANCH]` | Swap a branch into the main worktree (exchanges branches and gitignored files) |
| `prune [--min-age 1h]` | Remove worktrees already merged into default; safety: skips locked, main, current-last |
| `relocate [BRANCHES]` | Move worktrees to their templated paths when the path doesn't match |

`copy-ignored` filters: built-in excludes (`.bzr/ .hg/ .jj/ .pijul/ .sl/ .svn/ .conductor/ .entire/ .worktrees/`) + `[step.copy-ignored] exclude = [...]` config + per-repo `.worktreeinclude` (gitignore-style patterns; files must be both gitignored AND match an include).

`eval` is the way to expose template values to shell scripts:
```bash
PORT=$(wt step eval '{{ branch | hash_port }}')
curl http://localhost:$PORT/health
```

### `wt hook <TYPE> [NAME ...]`

Run hooks on demand (testing, manual triggers).

```bash
wt hook pre-merge                  # all pre-merge hooks
wt hook pre-merge test             # named "test" from both sources
wt hook pre-merge user:test        # user's only
wt hook pre-merge project:         # all project hooks
wt hook pre-start --branch=feat    # override a template variable
wt hook pre-merge -- extra args    # forward into {{ args }}
```

### `wt config`

| Subcommand | Purpose |
|---|---|
| `wt config shell install` | **Required** — installs the shell wrapper that lets `wt switch` change the parent shell's directory |
| `wt config create [--project]` | Create a starter `~/.config/worktrunk/config.toml` (or `.config/wt.toml`) with examples |
| `wt config show [--full]` | Print config file locations and merged contents; `--full` runs diagnostics |
| `wt config approvals add\|clear [--global]` | Manage saved approvals (`~/.config/worktrunk/approvals.toml`) |
| `wt config alias show <NAME>` / `dry-run <NAME>` | Inspect/preview an alias template |
| `wt config state default-branch [get\|set\|clear]` | Cached default branch (clear after a remote rename like `master`→`main`) |
| `wt config state logs [get\|clear]` | View/clear hook output and command audit logs |
| `wt config state ci-status [get\|clear]` | View/clear CI status cache |
| `wt config state marker [get\|set\|clear] [--branch=NAME]` | Custom emoji/text marker shown in `wt list` |
| `wt config state vars [get\|list\|set\|clear] [--branch=NAME]` | Per-branch variables (experimental); usable in templates as `{{ vars.<key> }}` |
| `wt config state clear` | Nuke all worktrunk data inside `.git/` |
