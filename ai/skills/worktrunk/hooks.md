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
