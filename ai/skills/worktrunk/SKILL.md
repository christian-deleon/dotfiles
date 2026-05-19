---
name: worktrunk
description: Authoring and using `worktrunk` (the `wt` CLI) for git worktree management. ALWAYS use when editing `~/.config/worktrunk/config.toml`, anything under `worktrunk/.config/worktrunk/` in this dotfiles repo, in repos with `.config/wt.toml`, or for prompts mentioning `wt`, `worktrunk`, worktree workflows, parallel agents, or 'add a hook', 'create a worktree', 'set up wt aliases', 'configure post-start'. Covers commands, hooks (post-start, pre-remove, etc.), templates, aliases, state, and Christian's existing dotfiles config.
compatibility: opencode
---

# Worktrunk

`worktrunk` (binary `wt`) is a git-worktree workflow manager. It addresses worktrees by **branch name** (not path), automates the create → work → merge → remove lifecycle, and runs hooks at every stage. Designed for parallel agent workflows where each agent gets its own working directory.

Mental model: think of `wt` as `git switch` for worktrees. `wt switch feat` finds-or-creates the worktree for branch `feat`; `wt remove` deletes the current worktree and the branch (when safe); `wt merge` squashes + rebases + fast-forwards the target + cleans up. The worktree's filesystem path is computed from a template — you never type it.

The most common AI failure mode here is reaching for raw `git worktree add` / `git worktree remove` instead of `wt switch --create` / `wt remove`. Use `wt`. Hooks, naming, and lifecycle behavior are part of the contract; bypassing them silently breaks the user's setup.

## Branch addressing

Every command that takes a branch accepts these shortcuts, in arguments and in `--base` / target slots:

| Shortcut | Resolves to |
|---|---|
| `^` | Default branch (main/master) |
| `@` | Current branch |
| `-` | Previous worktree (like `cd -`) |
| `pr:N` | GitHub PR #N's branch (needs `gh`) |
| `mr:N` | GitLab MR !N's branch (needs `glab`) |

Branch existence:
- Local branch exists → switch to its worktree (create the directory if missing).
- Only `origin/X` exists → auto-create local tracking branch.
- Doesn't exist anywhere → requires `--create` (or fails).

`pr:`/`mr:` cannot be combined with `--create`. For fork PRs, `wt` fetches the ref and configures `pushRemote` to the fork.

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

## Config layout

Three files merge top-down (system → user → project), with a `[projects."host/owner/repo"]` override block in user config for per-repo settings:

| File | Path | Trust | Use |
|---|---|---|---|
| User | `~/.config/worktrunk/config.toml` | Trusted (no approval) | Personal hooks, commit-gen, defaults |
| Project | `.config/wt.toml` (in repo, committed) | Approval-gated | Team-shared hooks, dev URL |
| System | platform-specific (`wt config show`) | — | Org defaults |
| Approvals | `~/.config/worktrunk/approvals.toml` | — | Saved per-project allow-list |

### User-config schema (most useful keys)

```toml
worktree-path = "{{ repo_path }}/../{{ repo }}.{{ branch | sanitize }}"  # default

[commit]
stage = "all"                  # "all" | "tracked" | "none"

[merge]
squash = true ; commit = true ; rebase = true ; remove = true ; verify = true ; ff = true

[remove]
delete-branch = true

[switch]
cd = true
[switch.picker]
pager = "delta --paging=never"

[list]
summary = false                # LLM branch summaries
full = false ; branches = false ; remotes = false
task-timeout-ms = 0 ; timeout-ms = 0
url = "http://localhost:{{ branch | hash_port }}"   # also valid in [projects.*.list]

[step.copy-ignored]
exclude = []                   # additional patterns to exclude

[forge]
platform = "github"            # or "gitlab"
hostname = "github.example.com"

[commit.generation]
command = "..."                # shell pipeline producing the message on stdout
template = "..."               # minijinja prompt for single commit
squash-template = "..."        # minijinja prompt for squashed commit

[aliases]
open = "open http://localhost:{{ branch | hash_port }}"

# Hooks live as top-level sections (see "Hooks" below):
[pre-start]   ; [post-start] ; [pre-commit]  ; [post-commit]
[pre-merge]   ; [post-merge]  ; [pre-remove] ; [post-remove]
[pre-switch]  ; [post-switch]

[projects."github.com/owner/repo"]
worktree-path = ".worktrees/{{ branch | sanitize }}"
list.full = true
merge.squash = false
pre-start.env = "cp .env.example .env"
aliases.deploy = "make deploy BRANCH={{ branch }}"
```

### Env-var overrides

Prefix `WORKTRUNK_`, kebab→SCREAMING_SNAKE, nested with `__`:

| Key | Var |
|---|---|
| `worktree-path` | `WORKTRUNK_WORKTREE_PATH` |
| `commit.generation.command` | `WORKTRUNK_COMMIT__GENERATION__COMMAND` |
| `commit.stage` | `WORKTRUNK_COMMIT__STAGE` |
| `list.summary` | `WORKTRUNK_LIST__SUMMARY` |

Useful for one-off overrides in aliases (e.g. wrapping a single `wt merge` to use `$EDITOR` instead of an LLM).

## Hooks

Ten lifecycle slots. `pre-*` are blocking — failure aborts the operation. `post-*` are detached and logged.

| Hook | Fires |
|---|---|
| `pre-switch` | Before resolving the branch / creating worktree (runs in source worktree) |
| `post-switch` | Backgrounded after every switch outcome |
| `pre-start` | Blocking when a new worktree is created — installs, env files |
| `post-start` | Backgrounded on new worktree — dev servers, watchers, cache copy |
| `pre-commit` / `post-commit` | Around each commit during merge — formatters/linters/typecheck |
| `pre-merge` | Blocking after rebase, before merge — tests, security |
| `post-merge` | Backgrounded after merge (in target worktree if it exists, else primary) |
| `pre-remove` | Blocking, in the worktree being removed — backup state |
| `post-remove` | Backgrounded after removal (in primary worktree, since the original is gone) |

### Three forms

```toml
# 1. String — single command
pre-start = "npm install"

# 2. Table — concurrent commands (deprecated for pre-* hooks; use pipeline)
[post-start]
server = "npm run dev"
watch  = "npm run watch"

# 3. Pipeline [[block]] — sequential blocks, concurrent within a block
[[post-start]]
copy = "wt step copy-ignored"

[[post-start]]
install = "pnpm install"
build   = "pnpm build"
```

A failing step aborts remaining pipeline steps. Use the pipeline form when one step depends on another (the canonical case is `copy-ignored` before `install`).

### Template variables

Bare names refer to the **operation's primary subject**: destination for switch/create, source for merge/remove. The other side is `{{ base }}` (switch) or `{{ target }}` (merge). Pre/post pairs share perspective — `{{ branch | hash_port }}` produces the same port in `post-start` and `post-remove`.

| Group | Variables |
|---|---|
| Active worktree | `branch`, `worktree_path`, `worktree_name`, `commit`, `short_commit`, `upstream` |
| Operation | `base`, `base_worktree_path`, `target`, `target_worktree_path`, `pr_number`, `pr_url` |
| Repository | `repo`, `repo_path`, `owner`, `primary_worktree_path`, `default_branch`, `remote`, `remote_url` |
| Execution | `cwd`, `hook_type`, `hook_name`, `args` |
| Custom | `vars.<key>` (set via `wt config state vars set`) |

`cwd ≠ worktree_path` in three cases: `pre-switch` (runs in source), `post-remove` (worktree gone, runs in primary), `post-merge` after removal (runs in target). Variables are shell-escaped — never wrap `"{{ x }}"` in extra quotes.

Run any hook with `-v` to print the resolved variable block (unset conditional vars marked `(unset)`). Hooks also receive the entire context as JSON on stdin — useful for `python3 scripts/setup.py`-style hooks.

### Filters and functions

| Filter / fn | Effect |
|---|---|
| `branch \| sanitize` | Replace `/` and `\` with `-` (filesystem-safe) |
| `branch \| sanitize_db` | Lowercase alphanumeric + `_`, no leading digit, ≤48 chars + 3-char hash |
| `branch \| sanitize_hash` | Filesystem-safe with collision-avoiding hash suffix |
| `branch \| hash` | 3-char base36 digest |
| `branch \| hash_port` | Stable port in `10000–19999` (the canonical "port per worktree" recipe) |
| `path \| dirname` / `basename` | Path component manipulation |
| `worktree_path_of_branch("main")` | Returns the path of a named branch's worktree, or empty |

Conditionals: `{% if upstream %}…{% endif %}`. Defaults: `{{ vars.features | default('default') }}`. `{{ args }}` is the space-joined shell-escaped tail of unmatched flags + tokens after `--`; index with `{{ args[0] }}`, length with `{{ args | length }}`.

### `--KEY=VALUE` smart routing

Any `--KEY=VALUE` on a hook/alias invocation:
- If a template references `{{ KEY }}`, binds that variable.
- Otherwise, forwards into `{{ args }}` as a literal.

Hyphens become underscores: `--my-var=x` → `{{ my_var }}`. Use `wt hook ... --branch=foo` to override the branch a hook sees without moving the actual worktree.

## Aliases and extensions

Three extension mechanisms:

1. **Hooks** — automatic, lifecycle-driven (above).
2. **Aliases** (`[aliases]` in TOML) — manual `wt <name>`. Same template engine as hooks. Pipelines via `[[aliases.NAME]]`. Listed via `wt config alias show <name>`, previewed via `... dry-run <name>`.
3. **Custom subcommands** — any executable named `wt-foo` on `PATH` becomes `wt foo`. Args pass through verbatim; no template engine. Built-ins > aliases > custom subcommands.

Aliases are the right tool for shell shortcuts you want template-rendered:

```toml
[aliases]
open  = "open http://localhost:{{ branch | hash_port }}"
mc    = '''WORKTRUNK_COMMIT__GENERATION__COMMAND='...editor pipeline...' wt merge'''
since = "git log --oneline {{ default_branch }}..HEAD"
s     = "wt switch {{ args }}"
```

`wt switch`, `wt merge`, `wt remove` invoked from inside an alias propagate directory changes through shell integration, but `cd`/`export` inside the alias body don't (subshell).

## Approvals & state

- **User hooks/aliases** are trusted (no prompt).
- **Project hooks/aliases** prompt on first run; saved to `~/.config/worktrunk/approvals.toml`. Re-approval needed when the command text changes.
- `--yes` / `-y` skips prompts (CI/automation).
- `wt config approvals add|clear` to pre-seed or wipe.

State lives in `.git/` (per-repo, never tracked):
- `git config worktrunk.*` — cached default branch, switch history, markers, vars.
- `.git/wt/cache/{kind}/*.json` — CI/git result caches; `.git/wt/cache/summary/{branch}/{hash}.json` — LLM summaries.
- `.git/wt/logs/{branch}/{source}/{hook-type}/{name}.log` — per-hook output (`source` ∈ `user`/`project`/`internal`).
- `.git/wt/logs/commands.jsonl` — audit log (rotates at 1MB → ~2MB total).
- `.git/wt/trash/<name>-<timestamp>` — staging area for backgrounded `wt remove`.

Tail a hook live: `tail -f "$(wt config state logs get --hook=user:post-start:server)"`.

## Repo-specific conventions (this dotfiles repo)

`worktrunk/.config/worktrunk/config.toml` is the **user** config (stowed via omadot from `~/.dotfiles/worktrunk/`). Current shape:

```toml
worktree-path = "../{{ branch | sanitize }}"   # NB: relative — sibling to repo root, no `<repo>.` prefix

[post-start]
agent-files = "dot agent link"                 # auto-link AGENTS.md / CLAUDE.md from agent-files submodule

[step.copy-ignored]
exclude = ["AGENTS.md", "CLAUDE.md"]           # defensive: don't dereference our managed symlinks

[commit.generation]
command = "CLAUDECODE= MAX_THINKING_TOKENS=0 claude -p --model=haiku ... | sed ..."
template = "...Conventional Commits 1.0.0..."

[list]
summary = true                                  # LLM branch summaries
```

Conventions:
- **`worktree-path` is non-default and shorter than upstream's default** (`../{{ branch | sanitize }}` vs `{{ repo_path }}/../{{ repo }}.{{ branch | sanitize }}`). Don't "fix" this back to the default — the short form is intentional.
- **`agent-files` post-start hook is global on purpose.** It's safe because `dot agent link` silent-skips when the project has no entry in the private `agent-files` submodule. See `CLAUDE.md` (`dot agent` section) before changing it.
- **`AGENTS.md` / `CLAUDE.md` MUST stay in `[step.copy-ignored] exclude`.** They're symlinks into the agent-files submodule; copying would dereference into a frozen file and break update propagation.
- **Commit-gen uses Claude Haiku via `claude -p`** with explicit `CLAUDECODE=` / `MAX_THINKING_TOKENS=0` to disable nesting guards and thinking. The template enforces Conventional Commits 1.0.0 — keep it that way, since other tooling in this repo (the `commit` skill, etc.) assumes it.
- **`list.summary = true` is a per-machine choice** (it costs an LLM call per branch on `wt list --full`). If you're authoring a setting that would massively change list cost (network, summary, ci-status), surface that in the commit message.
- This file is the **user** config. Project hooks belong in a project's `.config/wt.toml`, not here.

## Don't / Do

| Don't | Do |
|---|---|
| Reach for `git worktree add/remove` directly | `wt switch --create` / `wt remove` |
| `cd ../repo.feat` | `wt switch feat` (or `wt switch -` for previous) |
| Hard-code a port per worktree | `{{ branch \| hash_port }}` in `[post-start]` and `[pre-remove]` (same value both sides) |
| Wrap template vars in extra quotes (`"{{ branch }}"`) | Bare — they're auto shell-escaped |
| Use table form for `pre-*` hooks (deprecated) | `[[pre-merge]]` pipeline blocks |
| Run dependency installs in `post-start` (background, racy) | `pre-start` (blocking) — caller can rely on it being done |
| Put long-running servers in `pre-start` (blocks switching) | `post-start` (background) |
| Write `[post-start] copy = "wt step copy-ignored" ; install = "pnpm i"` (concurrent) | Pipeline: copy block, then install block — install needs the cache present |
| Edit files directly in `~/.config/worktrunk/` on this machine | Edit `~/.dotfiles/worktrunk/.config/worktrunk/` (it's stowed) |
| Drop `AGENTS.md` / `CLAUDE.md` from `[step.copy-ignored] exclude` | Keep them — they're managed symlinks |
| Use `--no-hooks` to "fix" a misbehaving hook | Investigate the hook; check `wt config state logs` and `.git/wt/logs/commands.jsonl` |
| Use `wt remove --force` reflexively for build artifacts | Add the directory to `.gitignore` so it's expected; `--force` is for genuine cleanup, not muscle memory |
| Hand-roll a worktree path | `wt step eval '{{ worktree_path_of_branch("main") }}'` |
| Switch to "the same branch in another worktree" by editing config | `wt step promote <branch>` swaps it into the main worktree |

## Adding to this skill

This skill grows with Christian's worktrunk usage. When a new pattern, hook, or alias becomes part of the dotfiles config — or when a project repeatedly needs a new convention — add a section. Keep examples short, lead with the rule, call out the "why" only when non-obvious. Defer git-itself mechanics elsewhere; this skill is for `wt`-specific behavior.
