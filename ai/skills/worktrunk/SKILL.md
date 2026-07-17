---
name: worktrunk
description: Authoring and using `worktrunk` (the `wt` CLI) for git worktree management. Use when editing `~/.config/worktrunk/config.toml`, in repos with `.config/wt.toml`, or for prompts about `wt`, worktree workflows, parallel agents, 'add a hook', 'create a worktree', 'configure post-start'. Covers commands, hooks, templates, aliases, state.
compatibility: opencode
---
# Worktrunk

`worktrunk` (binary `wt`) is a git-worktree workflow manager. It addresses worktrees by **branch name** (not path), automates the create → work → merge → remove lifecycle, and runs hooks at every stage. Designed for parallel agent workflows where each agent gets its own working directory.

Mental model: think of `wt` as `git switch` for worktrees. `wt switch feat` finds-or-creates the worktree for branch `feat`; `wt remove` deletes the current worktree and the branch (when safe); `wt merge` squashes + rebases + fast-forwards the target + cleans up. The worktree's filesystem path is computed from a template — you never type it.

The most common AI failure mode here is reaching for raw `git worktree add` / `git worktree remove` instead of `wt switch --create` / `wt remove`. Use `wt`. Hooks, naming, and lifecycle behavior are part of the contract; bypassing them silently breaks the user's setup.

## Decision tree

| Need | Read |
|---|---|
| CLI commands (`switch`, `merge`, `step`, …) | [commands.md](commands.md) |
| Config schema, env overrides, aliases, state | [config.md](config.md) |
| Lifecycle hooks, templates, filters | [hooks.md](hooks.md) |
| This repo's stowed user config conventions | section below |


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

## Repo-specific conventions (this dotfiles repo)

`worktrunk/.config/worktrunk/config.toml` is the **user** config (stowed via omadot from `~/.dotfiles/worktrunk/`). Current shape:

```toml
worktree-path = "../{{ branch | sanitize }}"   # NB: relative — sibling to repo root, no `<repo>.` prefix

[post-start]
agent-files = "dot agent link"                 # auto-link AGENTS.md / CLAUDE.md from agent-files submodule

[step.copy-ignored]
exclude = ["AGENTS.md", "CLAUDE.md"]           # defensive: don't dereference our managed symlinks

[commit.generation]
command = "$HOME/.dotfiles/scripts/worktrunk-commit-gen.sh"   # dispatcher; reads $AI_TOOL_PIPE
template = "...Conventional Commits 1.0.0..."

[list]
summary = true                                  # LLM branch summaries
```

Conventions:
- **`worktree-path` is non-default and shorter than upstream's default** (`../{{ branch | sanitize }}` vs `{{ repo_path }}/../{{ repo }}.{{ branch | sanitize }}`). Don't "fix" this back to the default — the short form is intentional.
- **`agent-files` post-start hook is global on purpose.** It's safe because `dot agent link` silent-skips when the project has no entry in the private `agent-files` submodule. See `CLAUDE.md` (`dot agent` section) before changing it.
- **`AGENTS.md` / `CLAUDE.md` MUST stay in `[step.copy-ignored] exclude`.** They're symlinks into the agent-files submodule; copying would dereference into a frozen file and break update propagation.
- **Commit-gen is dispatched through `scripts/worktrunk-commit-gen.sh`**, which picks the AI CLI from `$AI_TOOL_PIPE` (`claude`/`opencode`/`grok`) and auto-detects in `claude > opencode > grok` order if unset. Switch tools per-machine with `dot ai-tool` (which sets `AI_TOOL_PIPE` alongside `AI_TOOL`/`AI_TOOL_RESUME`), or per-shell with `AI_TOOL_PIPE=claude wt step commit`. Per-tool model overrides via `AI_PIPE_{CLAUDE,OPENCODE,GROK}_MODEL`. The template enforces Conventional Commits 1.0.0 — keep it that way, since other tooling in this repo (the `commit` skill, etc.) assumes it.
- **The dispatcher validates output against a Conventional Commits regex** before returning it to `wt`. Failure handling distinguishes the two modes you'll actually hit:
  - **Tool exits non-zero** (expired subscription, missing API key, network error): surfaces both the tool's stderr *and* stdout (claude in particular writes `Not logged in · Please run /login` to **stdout**, not stderr — so capturing stderr alone hides the cause), then exits 1 *without retrying*. A payment problem doesn't get better on the second call.
  - **Tool exits zero but output isn't valid CC** (model chattered, refused, wrapped in fences, or wrote an over-length subject): retries up to `$AI_PIPE_RETRIES` more times (default `2` → 3 total attempts). Each retry **appends the exact rejection reason** to the prompt (e.g. "the description after `docs: ` is 78 characters; the hard limit is 72") so the model corrects that specific attempt instead of regenerating another similar, still-invalid message. On final failure, dumps the last rejection reason and the last attempt's full output to stderr.
  Set `AI_PIPE_RETRIES=0` to disable retries entirely. **If you change the type list in `[commit.generation] template`, update `CC_REGEX` *and* `CC_PREFIX_REGEX` in the script too** — they must stay in sync.
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
