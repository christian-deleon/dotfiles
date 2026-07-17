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
