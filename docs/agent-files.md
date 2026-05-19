# Agent Files (`dot agent`)

`dot agent` manages two kinds of overlay agent files sourced from the private `agent-files` submodule. The submodule is namespaced:

```
agent-files/
  projects/<project-name>/AGENTS.md   # per-project (symlinked into project worktrees)
  env/<env-name>/AGENTS.md            # per-env global (symlinked into AI tool config paths)
```

Commits inside the submodule are made automatically with a generated message; **push is always manual** (`cd ~/.dotfiles/agent-files && git push`) so remote sync stays an explicit decision.

The implementation for both scopes lives in `scripts/dot/agent.sh` (`manage_agent_files`, `agent_*`, `agent_env_*` helpers) — sourced by `dot.sh`.

## Submodule lazy-init

`agent-files` is intentionally not initialized by the installer or by `dot update --init` — it's lazy-initialized the first time a `dot agent` subcommand needs it, and `dot update` only refreshes it if it's already initialized. This keeps locked-down machines (no SSH access to the private repo) working without errors.

## Per-project — `dot agent link`

For projects where `AGENTS.md` / `CLAUDE.md` cannot be committed to the project repo and `.gitignore` cannot be modified. The actual content lives in `agent-files/projects/<project>/AGENTS.md`; the project gets symlinks excluded via `.git/info/exclude`. There are no modes — this single flow is the only flow.

`dot agent link` ensures every worktree of the project has:
- `AGENTS.md` → `~/.dotfiles/agent-files/projects/<project>/AGENTS.md` (canonical source)
- `CLAUDE.md` → `AGENTS.md` (relative)

**Pre-flight:**

1. If `agent-files/projects/<name>/AGENTS.md` already exists, use it.
2. Else if `agent-files/projects/<name>/CLAUDE.md` exists alone, rename it to `AGENTS.md` inside the submodule (canonicalize) and commit.
3. Else if the cwd's worktree has an untracked `AGENTS.md` (or `CLAUDE.md`), migrate it into the submodule (renaming `CLAUDE.md` → `AGENTS.md` as needed) and commit. This is the "I just placed the file in the project; please move it where it belongs" path.
4. Else: implicit call → silent-skip; explicit `dot agent link <name>` → error.

**Both names are written into the shared `.git/info/exclude`** inside a `# >>> dot-agent-files >>>` / `# <<< dot-agent-files <<<` sentinel block. The exclude lives in the common git dir, so one write covers every worktree.

**Tracked-file refusal** — `agent_check_safe` will not overwrite a tracked file. If a project commits its own agent files, this tool isn't for that project — implicit calls silent-skip; explicit calls error. (We don't auto-create `CLAUDE.md` symlinks against committed `AGENTS.md` files; `dot agent` is only for the no-commit use case.)

**Project name resolution** — `[name]` defaults to the basename of the *project root* (parent of the common git dir), so it works correctly inside a worktrunk worktree where the cwd basename is the branch name. The exclude file itself is the shared one in the common git dir.

**Worktrunk integration** — the user config (`worktrunk/.config/worktrunk/config.toml`) defines `[post-start] agent-files = "dot agent link"` so every newly created worktree is set up automatically. It also ships `[step.copy-ignored] exclude = ["AGENTS.md", "CLAUDE.md"]` defensively so a project using `wt step copy-ignored` never dereferences our symlinks into a frozen file.

**Worktree removal** — no cleanup needed. Symlinks live inside the worktree dir, so `wt remove` / `git worktree remove` takes them with the directory. The sentinel block in the shared `.git/info/exclude` is harmless (patterns just don't match anything in the gone worktree). Adding a `pre-remove` hook for `dot agent unlink` would be wrong because `unlink` operates on every worktree.

## Per-env — `dot agent env link`

For environment-scoped context that isn't tied to a single project — e.g. "this machine is a locked-down WSL VM behind a corp proxy, network egress is restricted, X tool is unavailable." Content lives in `agent-files/env/<env-name>/AGENTS.md` and is symlinked into the global config paths of each AI tool on the current machine. Current targets (`AGENT_ENV_TARGETS` in `scripts/dot/agent.sh`):

- `~/.claude/CLAUDE.md` (Claude Code)
- `~/.config/opencode/AGENTS.md` (OpenCode)

`dot agent env link <name>` flow:

1. Lazy-init submodule.
2. If `env/<name>/AGENTS.md` doesn't exist: migrate the first existing target file we find (the "I already wrote it into `~/.claude/CLAUDE.md` — please move it where it belongs" path), else create an empty stub with a header comment. Either way, commit in the submodule.
3. Refuse to clobber any unmanaged regular file at a target path.
4. Drop symlinks at every target → `agent-files/env/<name>/AGENTS.md` (one source, N symlinks).

`dot agent env link` (no arg) re-links the currently linked env — derives the name from the existing symlink, so it's a safe no-op refresh.

**The symlinks themselves are the state.** No `.localrc` flag, no marker file — `dot agent env status` resolves the symlinks to report which env is active on this machine. To opt out: `dot agent env unlink`.

**Persistence across machines** — content lives in the private repo, so it's synced. To activate on a new machine: `dot agent env link <name>` once.

**Adding more AI tools** — just append to `AGENT_ENV_TARGETS` in `scripts/dot/agent.sh`. Existing linked machines will pick up the new target on next `dot agent env link` (with no arg).
