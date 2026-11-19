# Architecture

How the dotfiles repo is organized, installed, and integrated with the host system. Read this when you need to understand or modify the installer flow, omadot/Stow mechanics, host integration (Omarchy, SSH, submodules), or the AI config plumbing. For the bare-minimum "what's where" overview, see [../AGENTS.md](../AGENTS.md).

## Source into, never replace

The system (Omarchy, Ubuntu, macOS) owns `~/.bashrc`. Dotfiles provide customizations via `~/.commonrc` which is sourced into the system's shell config.

```
SYSTEM-OWNED (never symlinked)          DOTFILES (symlinked from ~/.dotfiles/)
─────────────────────────────           ──────────────────────────────────────
~/.bashrc (Omarchy / Ubuntu / etc.)     ~/.commonrc ─┬─ ~/.aliases
  └── source ~/.commonrc                             ├── ~/.functions ── sources ~/.dotfiles/functions.d/*.sh
                                                     └── ~/.localrc (not tracked)
~/.zshrc (macOS, symlinked)
  └── source ~/.commonrc
```

`.bashrc` is never symlinked. `install.sh` injects `source ~/.commonrc` into the system's existing `~/.bashrc`. Machine-specific config (`EDITOR`, secrets, env vars) goes in `~/.localrc` (not tracked).

### XDG base directories

`.commonrc` exports `XDG_CONFIG_HOME` / `XDG_DATA_HOME` / `XDG_STATE_HOME` / `XDG_CACHE_HOME` to the usual `~/.config`, `~/.local/share`, `~/.local/state`, and `~/.cache` paths when they are unset. Linux often sets these via PAM; **macOS does not**. Without them, Go tools such as k9s use `~/Library/Application Support` and ignore stowed `~/.config/<tool>` configs. Values already set (e.g. in `~/.localrc`) are left alone.

### Shell loading order

**On Omarchy/Linux (bash):**

1. Omarchy's `~/.bashrc` → sources Omarchy defaults (starship, mise, zoxide, etc.)
2. `~/.bashrc` → sources `~/.commonrc` (injected by install.sh)
3. `.commonrc` → sources `.aliases`, `.functions`, `.localrc`

**On macOS (zsh):**

1. `.zshrc` → Homebrew, Oh My Zsh, Powerlevel10k, zsh plugins
2. `.zshrc` → sources `.commonrc`
3. `.commonrc` → sources `.aliases`, `.functions`, `.localrc`
4. `.zshrc` → fzf, `.p10k.zsh`

## Installer flow

`install.sh` is only the bootstrap: it sources `scripts/lib.sh` (see [Library](#library--scriptslibsh)), runs core config, then a **profile** or **Manual selection**. `dot.sh` sources the same library and never sources `install.sh`.

1. **Core config** (always): stale-link cleanup, tombstones, legacy path migration, `.commonrc`, `.aliases`, `.functions` + inject into `.bashrc` (on macOS also the `.zshrc` and `.gitconfig` links), plus `dot` CLI linked to `~/.local/bin`. (`.functions` is a loader that sources `~/.dotfiles/functions.d/*.sh` directly — no separate symlink for the fragments dir.)
2. **Profile picker**: one menu showing every profile in `profiles/*.yaml` whose `requires:` predicates pass on the host, with "Manual selection" appended. `./install.sh --profile <name>` skips the picker. Picking a profile runs its `core_extras:` and installs its `items:`, then writes `~/.dotfiles/.active-profile` (also when an item failed, so `dot update` keeps reconciling it). The `ai-tool` extra runs after the items, because it picks among the installed harnesses. Manual mode shows the core-extras picker and the full item picker, but writes no profile state.

Prompts (`read`, `gum`) run only when stdin and stdout are both a terminal (`_interactive`). Without one, `./install.sh` with no `--profile` exits with "pass --profile <name>" before touching `$HOME`, `dot install` refuses the picker and manual mode the same way, and `--profile` runs with no prompt at all.

Schema references: [manifest.md](manifest.md) for item entries, [profiles.md](profiles.md) for profile YAMLs. Predicates live in `scripts/predicates.sh` (`linux`, `darwin`, `wsl`, `amazonlinux`, `omarchy`, `hyprland`, `fprintd`).

**Item kinds** (from manifest blocks):
- `tool` — `install:` block only (e.g. `docker`, `jq`)
- `config` — `config:` block only (e.g. `btop`)
- `bundle` — both blocks; picker tags with `(+ config)` (e.g. `alacritty`, `neovim`, `tmux`)

**Config types** (only two): `stow` (auto-stow from `<pkg>/.config/<pkg>/`) and `handler` (named bash function in `scripts/handlers/*.sh`).

**Only missing work is done.** `install_items` (`scripts/lib/engine.sh`) skips items already present, installs every missing package in one package-manager call, then release downloads and install scripts; it re-links only stow configs whose link is wrong, and runs each handler and `post_install` hook once per process (`run_once`). Details: [manifest.md](manifest.md#how-an-install-runs).

**Failed installs don't abort the rest** — `install_items` collects failures, including a missing stow package, and warns at the end. `install.sh` then exits non-zero with "Dotfiles setup finished with failures".

**Backups and links:** `link_file` and `install_stow_config` leave a link that already points at the right target alone. Anything they replace is copied into `~/dotfiles_backup` first; an existing backup is never overwritten (the next free `.N` suffix is used), so the first backup stays the original.

**MCP / 1Password graceful degradation:** `generate_mcp_configs` (the post-install hook for `grok`, `opencode`, and `claude`) drops any enabled MCP server whose JSON contains an unresolved `op://` reference when `op` is missing or fails to connect. The remaining keyless servers are still configured. Which servers are enabled comes from the profile's `mcp:` block ([profiles.md](profiles.md)).

## App config management (Stow + omadot)

App configs in `~/.config/` are managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot) on all platforms:

- Configs are stored as stow packages in `~/.dotfiles/<pkg>/.config/<pkg>/`
- `omadot put <pkg>` creates directory-level symlinks: `~/.config/<pkg>` → `~/.dotfiles/<pkg>/.config/<pkg>`
- New files in `~/.config/<pkg>/` automatically appear in the repo (no re-run needed)
- Stow packages are **declared in `manifest.yaml`** with `config.type: stow` — the installer does not auto-discover them from the filesystem. Adding a new stow config requires a manifest entry. Single-file packages (e.g. `starship/.config/starship.toml`) are handled by the same dispatcher.

**Special configs** (manifest `config.type: handler`, dispatched to functions in `scripts/handlers/*.sh`):
- `grok` — Grok Build config from `ai/` + `grok/.grok/` (`install_ai_grok`); MCP is merged into live `~/.grok/config.toml`
- `claude` — Claude Code config from `ai/` (`install_ai_claude`); skills/agents/rules symlink into `~/.claude/`; hooks merge into `settings.json`; MCP merges into `~/.claude.json`
- `cargo` — links `cargo/.cargo/config.toml` into `~/.cargo/config.toml` (`install_cargo_config`)
- `cargo-sweep` — links `cargo-sweep/systemd/*` into `~/.config/systemd/user` and enables `cargo-sweep-athenis.timer`, a daily `cargo sweep --maxsize 150GB` of the shared Athenis build dir (`install_cargo_sweep_timer`). Size cap, not `--time`: cargo-sweep ages files by atime, which any recursive read resets
- `windows-terminal` — WSL-side script wrapper (`install_windows_terminal_config`)
- `hypr` / `omarchy` — copy personal overlays into Omarchy-owned real directories (`install_hypr_config`, `install_omarchy_config` in `scripts/handlers/desktop.sh`)

Stow + post_install (not handlers): `opencode` (stow config + `install_ai_opencode` + `generate_mcp_configs`), `tmux` (stow under `tmux/.config/tmux/`).

**Not managed by omadot:**
- `~/.config/git/` (Omarchy-owned)
- `~/.config/hypr` and `~/.config/omarchy` (Omarchy-owned real directories; see below)

**Never use `omadot put hypr` or `omadot put omarchy`.** That would replace the real directory with a git symlink and make the next Omarchy update write into the repo.

**Never use `omadot put --all`** in this repo. It would try to stow non-package directories (`brew/`, `scripts/`, `docs/`, etc.).

**Stale-symlink cleanup (`clean_stale_dotfile_symlinks`):** when a stow package is removed from the repo, the `~/.config/<pkg>` symlink on each machine becomes a dangling pointer into `$DOTFILES_DIR/<pkg>/`. `clean_stale_dotfile_symlinks()` in `scripts/lib/fs.sh` scans `~/.config/` (depth 1), removes any symlink that resolves into `$DOTFILES_DIR/` and whose target no longer exists. It runs at the top of `run_core_config()` (every `./install.sh`) and in the hygiene phase of `dot update`. One function, two call sites — generalization of `clean_ai_symlinks()`.

**Tombstones (`apply_tombstones`):** path-only **desired absences** for residue that is not a dangling stow link (script installs under `~/.local/share`, XDG cache/state, home files like `.blerc`). Declared in repo-root `tombstones.yaml`; applied idempotently by `apply_tombstones()` in `scripts/lib/engine.sh` on every `dot update` and during `run_core_config()`. Not a migration ledger — re-check forever, no-op when clean. Does not uninstall OS packages. Full schema and when-to-use: [tombstones.md](tombstones.md).

## Omarchy compatibility

On [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland):

- Omarchy owns `~/.bashrc` and sources its defaults (starship, mise, zoxide, eza, etc.)
- Dotfiles layer on top via `.commonrc` — never replace Omarchy's shell setup
- Omarchy owns `~/.config/hypr` and `~/.config/omarchy` as **real directories**. Package defaults live in `/usr/share/omarchy/default/`; stock user templates in `/usr/share/omarchy/config/`. This repo copies only personal overlays (`hypr/overlays/*.lua`, monitor scripts, custom themes, branding) into those directories. Shell settings in `~/.config/omarchy/shell.json` are not copied: `omarchy/shell.overlay.json` is merged into the file key by key, because Omarchy treats `shell.json` as authoritative and does not merge its defaults back in. Plugin entries are matched by `id` and only updated if the plugin is already enabled. `omarchy refresh hyprland` restores stock templates without touching git; `dot update` and `~/.config/omarchy/hooks/post-update.d/reapply-desktop-overlays` put overlays back.
- Do not commit a file just because an Omarchy update created it under `~/.config/hypr` or `~/.config/omarchy`. Diff against `/usr/share/omarchy/config/` to see whether it is stock.
- Active theme files live in `~/.local/state/omarchy/current/` (generated). They are not tracked.
- Dotfiles own `~/.config/starship.toml` (stowed from `starship/.config/starship.toml`); seeded byte-for-byte from Omarchy's default and evolved from there. `.commonrc` initializes starship on bash with a `$STARSHIP_SHELL` guard to avoid double-init on Omarchy.
- 1Password SSH agent path: `/opt/1Password/op-ssh-sign` (Linux) vs `/Applications/1Password.app/Contents/MacOS/op-ssh-sign` (macOS)
- 1Password SSH socket: `~/.1password/agent.sock` (Linux) vs `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` (macOS)

## Git submodules

| Submodule | Path | Branch | Purpose |
|-----------|------|--------|---------|
| tpm | `.tmux/plugins/tpm` | default | Tmux plugin manager |
| ssh-config | `.ssh` | main | Shared SSH host entries |
| omarchy themes | `omarchy/.config/omarchy/themes/*` | default | Omarchy theme submodules |
| agent-files | `agent-files` | main | Per-project & per-env AGENTS.md overlays — lazy-init via `dot agent` (see [dot-agent.md](dot-agent.md)) |

`.ssh` and tpm are initialized by `install_git_submodules()` (the `git-submodules` core extra; a profile without `ssh-config` skips `.ssh`). Files deleted from `.ssh`'s working tree are checked out again; uncommitted edits there are reported and kept. Theme submodules are initialized by the `omarchy-themes` extra, `agent-files` lazily by `dot agent`. Both the installer and `dot update` set `push.recurseSubmodules=on-demand` in the repo-local git config, so pushing the parent pushes any referenced submodule commits first.

`dot update` updates only initialized submodules (see [Network and 1Password](#network-and-1password)):

- **Branch-tracking (private) ones** — those with `branch =` in `.gitmodules` (`.ssh`, `agent-files`) — are fetched over SSH and fast-forwarded to `origin/<branch>` locally. A submodule with commits that are not on origin is left as is with a warning, and so is a parent gitlink that points at a commit origin does not have.
- **Pinned (public) ones** (tpm, initialized themes) update together in one background `git submodule update --remote --jobs 4`.

Submodule failures warn and never abort the update.

## SSH config

- `.ssh/` is a git submodule containing shared host entries (no OS-specific settings)
- `~/.ssh/config` is **not** a symlink — it's a generated file created by `install.sh` that:
  1. Sets the correct `IdentityAgent` for the current OS (1Password socket path)
  2. `Include`s the shared submodule config
- Never put OS-specific paths (like `IdentityAgent`) in the submodule config

## Library — `scripts/lib.sh`

Every installable item — tool binaries, stow configs, special handlers — is declared in `manifest.yaml`. Profiles in `profiles/*.yaml` curate which items run on which machine context. See [manifest.md](manifest.md) and [profiles.md](profiles.md) for full schema reference.

`scripts/lib.sh` is a loader, sourced once per process by `install.sh` and `dot.sh`. It loads `scripts/lib/*.sh` in the order below, then `scripts/predicates.sh`, then every `scripts/handlers/*.sh`. Every file only defines functions and globals, so sourcing has no other effect. The modules are bash 3.2-safe (macOS `/bin/bash`) and use jq 1.6 features only.

| Module | Holds |
|---|---|
| `log.sh` | `_info` / `_success` / `_warn` / `_error`, phase timing and the change summary (`phase_start`, `note_change`, `print_summary`), `_interactive` |
| `fs.sh` | `resolve_path`, `xdg_root`, `backup_item`, `link_file`, `ensure_link`, link cleanup (`clean_ai_symlinks`, `clean_stale_dotfile_symlinks`, `migrate_legacy_dotfiles_symlinks`) |
| `pkg.sh` | `detect_pkg_manager` (`arch`, `apt`, `brew`, `dnf`), batched `pkg_install`, `ensure_homebrew` / `ensure_yq` / `ensure_jq` / `ensure_stow` / `ensure_omadot` / `ensure_gum` |
| `release.sh` | `install.release` downloads ([manifest.md](manifest.md#installrelease)) |
| `data.sh` | YAML loading, manifest and profile accessors, the AI harness registry, 1Password helpers (`op_ready`, `op_inject_multi`) |
| `engine.sh` | `install_items`, `run_once`, `apply_tombstones`, `install_stow_config` |
| `git.sh` | remote split, dotfiles pull, submodule init and update, theme submodules |
| `core.sh` | core config pieces (shell, zsh, git and SSH config, dot CLI, `bin/` links), the core-extras table, profile picker and installers |

**YAML is read once.** `_yq_json` turns each YAML file into JSON once per process (`manifest.yaml`, the active profile, `tombstones.yaml`, `ai/models.yaml`); every lookup after that is `jq`. It works with either yq on `PATH`: Python yq (Arch) or mikefarah's Go yq. Load the data in the calling shell (`data_load` or one `data_load_*`), never inside `$(…)`, or the cache is lost with the subshell. `ensure_yq` installs yq when it is missing: from Homebrew on macOS, from the Go yq GitHub release on Linux.

Manifest accessors in `data.sh`:
- `manifest_list_all` — list every item key
- `manifest_resolve_alias <name>` — resolve `op` → `1password-cli`, `nvim` → `neovim`, etc.
- `manifest_kind <item>` — returns `tool` / `config` / `bundle`
- `manifest_field <item> <jq-path>` — generic field read (e.g. `manifest_field docker .install.arch`)
- `manifest_post_install <item>` — list post_install hook names
- `manifest_requires_met <item>` — check `requires:` predicates against the host
- `manifest_label <item>` — picker label with `(+ config)` suffix for bundles

Custom config handlers live in `scripts/handlers/*.sh` (`ai.sh`, `alacritty.sh`, `cargo.sh`, `desktop.sh`, `gitea.sh`, `neovim.sh`, `superwhisper.sh`, `windows.sh`) and are referenced by name from `manifest.yaml`. Install scripts in `scripts/tools/install-*.sh` are referenced via `install.script`, for tools a release download cannot cover.

## `dot update`

`update_dotfiles` in `dot.sh` runs these phases in order:

| Phase | What runs |
|---|---|
| `preflight` | `ensure_yq`, `ensure_jq`; stop on merge conflicts in the dotfiles repo (on a terminal, offer a hard reset to upstream) |
| `pull` | Split the dotfiles remote, then `git pull --rebase --autostash --no-recurse-submodules`. When HEAD moved, re-run the new `dot.sh update` to finish (shown as `restart`) |
| `submodules` | Split the remotes of the owner's public submodules, sync URLs that changed in `.gitmodules`, update the initialized submodules |
| `hygiene` | `link_dot_bins` (`bin/wto` → `~/.local/bin`), `clean_stale_dotfile_symlinks` |
| `tombstones` | `apply_tombstones` |
| `reconcile` | `reconcile_profile`: `install_items` over the active profile's `items:` (add-only; skipped without a compatible active profile) |
| `ai` | `install_ai_<h>` for each enabled harness that reconcile did not already run |
| `agents` | `agent_env_refresh`, then `install_ai_tool_default` |

Only a failed dotfiles pull aborts the update. It ends with a summary: each change it made on disk (`note_change`) and the seconds per phase. A second run in a row prints "No changes". OS package upgrades are not part of `dot update`; they are the `pkgup` shell function.

### Network and 1Password

- **HTTPS fetch, SSH push.** `git_split_remote` gives a GitHub `origin` an HTTPS fetch URL and, when no `pushurl` is set, the SSH form as `pushurl`. It applies to the dotfiles repo and to the initialized submodules of the same GitHub owner that track no branch; `.gitmodules` lists theme URLs over HTTPS. A dotfiles pull that fails on authentication over HTTPS is retried once over the SSH push URL.
- **Private submodules** (`.ssh`, `agent-files`) share one SSH connection: the first fetch opens a `ControlMaster` in a temp dir scoped to the run (one SSH agent approval), the rest reuse it in the background. With no SSH agent socket and no `~/.ssh/id_*` key they are skipped with a warning.
- **Public submodules** update in parallel with those fetches.
- **1Password** is needed only for the private submodules (SSH agent), MCP secret injection (only when the MCP inputs changed, see [Shared MCP configuration](#shared-mcp-configuration)), and the `tea` login (only when it is missing). `op_inject_multi` substitutes each secret literally and JSON-safe, so `&`, `\` and `"` survive.

## System detection

- Auto-detect OS: `$OSTYPE` (macOS vs Linux)
- Detect Omarchy: `[[ -d "$HOME/.local/share/omarchy" ]]`
- Detect package manager: `detect_pkg_manager()` in `scripts/lib/pkg.sh`
- macOS: Homebrew for packages (auto-installed by `install.sh` if missing)
- Arch Linux: pacman/yay for packages
- Debian/Ubuntu: apt, with `install.release` downloads or scripts for tools apt lacks (`bat` and `fd` come from their releases, since apt ships them as `batcat` / `fdfind`)
- Amazon Linux 2023: dnf; no stow, so stow packages are linked directly

## AI config (`ai/`)

Shared AI agent configuration owned by this dotfiles repo at `~/.dotfiles/ai/`. Grok Build, OpenCode, and Claude Code are peer harnesses: each has its own installer that links or generates straight from `ai/` into its own tree, and none reads another harness's files. For directory layout and how to add skills/agents/rules, see [ai.md](ai.md).

**Which harnesses are configured:** `scripts/lib/data.sh` holds the registry (`AI_HARNESSES=(claude grok opencode)`, path helpers, `read_active_profile`, `profile_mcp_json`, `profile_ai_default`). `ai_harness_enabled <h>` is true when the active profile lists `<h>` in `items:`, or, with no active profile, when the harness is installed. Every installer and MCP writer returns early for a harness that is not enabled. With an active profile, `dot install`, `install_items`, and the manual picker refuse a harness the profile doesn't list (`ai_harness_allowed`).

**What `install_ai_grok()` does:**
- Symlinks `ai/skills/*`, `ai/agents/*`, and `ai/hooks/*` into `~/.grok/{skills,agents,hooks}/` (`ai/hooks/dotfiles.json` registers the hooks)
- Flattens `ai/rules/**/*.md` into `~/.grok/rules/<basename>.md`
- Seeds `~/.grok/config.toml` from `grok/.grok/config.toml` only if missing; never overwrites the live file
- Forces `[compat.claude]` off (the Claude installer fills `~/.claude`, so Grok would load everything twice) and `[folder_trust] enabled = false`; merges trusted folders
- Always upserts `grok/.grok/base.toml` into the live file
- If `grok/.grok/overlays/<active-profile>.toml` exists, upserts it after the base (e.g. work Bedrock). Overlays hold Grok-only settings; MCP tables in an overlay are ignored with a warning. Profile wins on conflict; `model.*` overlay tables replace wholesale.
- Symlinks `pager.toml`

**What `install_ai_opencode()` does** (skips until `~/.config/opencode` is stowed; never creates it):
- Links each `ai/skills/<name>` into `~/.config/opencode/skills/` (a real dir inside the stowed, gitignored package dir). OpenCode also reads `~/.claude/skills`; duplicates resolve by precedence to the same files.
- Runs `ai/scripts/generate-opencode-config.sh`, which builds agents (from `ai/agents/*.md`) and `instructions` (paths of `ai/rules/**/*.md`) into `opencode.json` in one jq pass and re-applies `.provider` from `opencode.json.tpl`. The file is written only when it changes, mode 600 from the start (it holds MCP secrets).
- Reloads the background OpenCode service only when `opencode.json` changed, at most once per run (the MCP writer shares the same reload)

**What `install_ai_claude()` does:**
- Symlinks `ai/skills/*` into `~/.claude/skills/` (skipping Claude's reserved `skills/synced`) and `ai/agents/*` into `~/.claude/agents/`; flattens rules into `~/.claude/rules/`
- `ensure_claude_settings` merges the Stop / Notification (permission and elicitation prompts only) / UserPromptSubmit command hooks into `~/.claude/settings.json`
- Sets `attribution` to `{commit: "", pr: "", sessionUrl: false}` in the same file so Claude never adds `Co-Authored-By` trailers, PR bylines, or session links

**Hooks:** scripts live once in `ai/hooks/`; registration is per harness (Grok via `ai/hooks/dotfiles.json`, Claude via the `settings.json` merge above, OpenCode via the `opencode/.config/opencode/plugins/notify-sound/tui.js` plugin that calls `stop_notify.sh`). Grok's hook payload is camelCase and Claude's is snake_case, so shared scripts read only fields spelled the same in both (e.g. `cwd`).

**Per-env instructions:** `dot agent env link` links `agent-files/env/<name>/AGENTS.md` into each enabled harness's user instructions file. See [dot-agent.md](dot-agent.md).

**Shared MCP:** `generate_mcp_configs()` (post_install on `grok`, `opencode`, and `claude`, or `dot mcp-regen`) — see [Shared MCP configuration](#shared-mcp-configuration).

**`dot update`:** after `reconcile_profile`, runs `install_ai_<h>` for each enabled harness the reconcile did not already install, then `agent_env_refresh` (re-links the current env's targets and skills, drops legacy hops) and `install_ai_tool_default`.

**Default harness:** profile `ai.default` picks the harness for `tav`/`wtc`/`wta`. The `ai-tool` core extra and `dot update` write `AI_TOOL` / `AI_TOOL_RESUME` into `~/.localrc` from it only when `~/.localrc` has no `AI_TOOL`. `dot ai-tool [TOOL]` overrides; its picker lists only enabled harnesses.

**Idempotency:** skill, agent and rule links that already point at the right `ai/` entry are kept, so running sessions never see one vanish; only missing or wrong links are made. `clean_ai_symlinks()` then removes the other links in the target directory that point into `~/.dotfiles/ai/` (or legacy `ecc/`). Agents with a `job:` are rendered files, rewritten only when their content changes and kept as they are when `ai/models.yaml` cannot be resolved.

**1Password:** `op_inject_multi()` resolves `op://` secret references across multiple 1Password accounts by building a vault-to-account map and using `op read` per-secret (standard `op inject` only supports one account per call).

## Methodologies

### Symlink strategy: merge vs replace

Use `link_file` (symlinks the entire directory) when the directory is exclusively owned by one source. Use per-item links when personal files need to coexist alongside sourced files: `link_ai_entries` in `scripts/handlers/ai.sh` links each `ai/` skill, agent, and hook into a harness's own dir, so personal and env skills sit next to them.

### Dynamic config merging

When two sources contribute to a single config file (e.g., generated AI agents + personal config in `opencode.json`), merge at install time using `jq -s '.[0] * .[1]'` rather than maintaining a combined copy. The base config comes first, personal overrides second (wins on conflicts). This eliminates duplication and keeps each source independently maintainable.

### Shared MCP configuration

MCP servers are defined once in `~/.dotfiles/ai/mcp-servers.json.tpl` (`command`/`args`/`env`/`url` JSON with `op://` secret references; `"default": true` on context7 and firecrawl). When a `dot agent` env is linked, `agent-files/env/<name>/mcp.json` is deep-merged onto that roster first (`env` and `headers` key by key; unknown server names are dropped). That file is how a machine adds hosts and credential commands without putting them in this repo. The active profile's `mcp:` block is the only source of truth for which servers run: `mcp.enable` picks them (the roster's `default: true` servers when there is no profile or no block) and `mcp.override.<server>` patches launch fields. Overrides apply after the env merge; then `$HOME` is expanded in the template, before 1Password injection, so a secret's own text is never edited. Only enabled servers are resolved, so unused servers' secrets are never fetched or written. The regen hash includes the env overlay, so editing it retriggers a write.

`generate_mcp_configs` writes exactly the enabled set to every enabled harness:
- **Grok** (`write_grok_mcp`): `[mcp_servers.*]` in live `~/.grok/config.toml` via `ai/scripts/merge-grok-mcp.py` (one run, atomic replace), which also removes those names from `[tools] disabled_mcp_servers`
- **OpenCode** (`write_opencode_mcp`): `mcp.servers` in `~/.config/opencode/opencode.json`
- **Claude Code** (`write_claude_mcp`): `mcpServers` in `~/.claude.json`; roster names not enabled are removed, hand-added non-roster servers stay

Each writer replaces its file only when the result differs. Hand toggles inside a harness are reset by the next regen. The run, and with it every 1Password call, is skipped when `~/.cache/dotfiles/mcp-servers.hash` (roster + profile `mcp:` block + harness list) is unchanged and each harness still has the names recorded in `~/.cache/dotfiles/<harness>-mcp-servers`. The hash is saved only when every harness took the write, so a failed one is retried next run. `dot mcp-regen` forces a run.

### Gitignore for generated symlinks in stowed dirs

When creating symlinks inside a stowed directory (e.g., `~/.config/opencode/commands/`), those symlinks resolve through the stow symlink into the dotfiles git tree and show as unstaged changes. Add them to the package's `.gitignore` to prevent this.

## Tool-specific notes

- **Kubernetes:** configs in `~/.kube/`, use `kcs` (select config), `kca` (load all)
- **fzf:** many functions (`kcs`, `kn`, `kc`, `kl`, `ke`, etc.) use fzf when no args provided
- **1Password:** `opl` function for CLI login, SSH agent for git signing
