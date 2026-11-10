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

The installer is always interactive. Core config (shell + dot CLI) runs unconditionally; then the user picks a **profile** or **Manual selection**:

1. **Core config** (always): `.commonrc`, `.aliases`, `.functions` + inject into `.bashrc`, plus `dot` CLI linked to `~/.local/bin`. (`.functions` is a loader that sources `~/.dotfiles/functions.d/*.sh` directly — no separate symlink for the fragments dir.)
2. **Profile picker**: one menu showing every profile in `profiles/*.yaml` whose `requires:` predicates pass on the host, with "Manual selection" appended. Picking a profile runs its `core_extras:` and installs its `items:` end-to-end, then writes `~/.dotfiles/.active-profile`. Manual mode shows the core-extras picker and the full item picker, but writes no profile state.

Schema references: [manifest.md](manifest.md) for item entries, [profiles.md](profiles.md) for profile YAMLs. Predicates live in `scripts/predicates.sh` (`linux`, `darwin`, `wsl`, `omarchy`, `hyprland`, `fprintd`).

**Item kinds** (from manifest blocks):
- `tool` — `install:` block only (e.g. `docker`, `jq`)
- `config` — `config:` block only (e.g. `btop`)
- `bundle` — both blocks; picker tags with `(+ config)` (e.g. `alacritty`, `neovim`, `tmux`)

**Config types** (only two): `stow` (auto-stow from `<pkg>/.config/<pkg>/`) and `handler` (named bash function in `scripts/handlers/*.sh`).

**Failed installs don't abort the rest** — `install_tools` collects failures and warns at the end.

**MCP / 1Password graceful degradation:** `generate_mcp_configs` (the post-install hook for `grok`, `opencode`, and `claude`) drops any enabled MCP server whose JSON contains an unresolved `op://` reference when `op` is missing or fails to connect. The remaining keyless servers are still configured. Which servers are enabled comes from the profile's `mcp:` block ([profiles.md](profiles.md)).

## App config management (Stow + omadot)

App configs in `~/.config/` are managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot) on all platforms:

- Configs are stored as stow packages in `~/.dotfiles/<pkg>/.config/<pkg>/`
- `omadot put <pkg>` creates directory-level symlinks: `~/.config/<pkg>` → `~/.dotfiles/<pkg>/.config/<pkg>`
- New files in `~/.config/<pkg>/` automatically appear in the repo (no re-run needed)
- Stow packages are **declared in `manifest.yaml`** with `config.type: stow` — the installer no longer auto-discovers them from the filesystem. Adding a new stow config requires a manifest entry. Single-file packages (e.g. `starship/.config/starship.toml`) are handled by the same dispatcher.

**Special configs** (manifest `config.type: handler`, dispatched to functions in `scripts/handlers/*.sh`):
- `grok` — Grok Build config from `ai/` + `grok/.grok/` (`install_ai_grok`); MCP is merged into live `~/.grok/config.toml`
- `claude` — Claude Code config from `ai/` (`install_ai_claude`); skills/agents/rules symlink into `~/.claude/`; hooks merge into `settings.json`; MCP merges into `~/.claude.json`
- `cargo` — links `cargo/.cargo/config.toml` into `~/.cargo/config.toml` (`install_cargo_config`)
- `windows-terminal` — WSL-side script wrapper (`install_windows_terminal_config`)
- `hypr` / `omarchy` — copy personal overlays into Omarchy-owned real directories (`install_hypr_config`, `install_omarchy_config` in `scripts/handlers/desktop.sh`)

Stow + post_install (not handlers): `opencode` (stow config + `install_ai_opencode` + `generate_mcp_configs`), `tmux` (stow under `tmux/.config/tmux/`).

**Not managed by omadot:**
- `~/.config/git/` (Omarchy-owned)
- `~/.config/hypr` and `~/.config/omarchy` (Omarchy-owned real directories; see below)

**Never use `omadot put hypr` or `omadot put omarchy`.** That would replace the real directory with a git symlink and make the next Omarchy update write into the repo.

**Never use `omadot put --all`** in this repo. It would try to stow non-package directories (`brew/`, `scripts/`, `docs/`, etc.).

**Stale-symlink cleanup (`clean_stale_dotfile_symlinks`):** when a stow package is removed from the repo, the `~/.config/<pkg>` symlink on each machine becomes a dangling pointer into `$DOTFILES_DIR/<pkg>/`. `clean_stale_dotfile_symlinks()` in `install.sh` scans `~/.config/` (depth 1), removes any symlink that resolves into `$DOTFILES_DIR/` and whose target no longer exists. It runs at the top of `run_core_config()` (every `./install.sh` and `dot install`) and from `dot.sh:update_dotfiles()` after the AI reinstall (every `dot update`). One function, two call sites — generalization of `clean_ai_symlinks()`.

**Tombstones (`apply_tombstones`):** path-only **desired absences** for residue that is not a dangling stow link (script installs under `~/.local/share`, XDG cache/state, home files like `.blerc`). Declared in repo-root `tombstones.yaml`; applied idempotently by `apply_tombstones()` in `scripts/lib.sh` on every `dot update` and during `run_core_config()`. Not a migration ledger — re-check forever, no-op when clean. Does not uninstall OS packages. Full schema and when-to-use: [tombstones.md](tombstones.md).

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

Submodules are initialized by `install_git_submodules()` during core config. `dot update` pulls already-initialized branch-tracking submodules (`.ssh`, `agent-files`) with `_submodule_pull_branch` (stay on `branch =`, then fail if the parent gitlink SHA is missing from origin). Pinned submodules (tpm, themes) still use `git submodule update --remote`. Both the installer and `dot update` set `push.recurseSubmodules=on-demand` in the repo-local git config, so pushing the parent pushes any referenced submodule commits first.

## SSH config

- `.ssh/` is a git submodule containing shared host entries (no OS-specific settings)
- `~/.ssh/config` is **not** a symlink — it's a generated file created by `install.sh` that:
  1. Sets the correct `IdentityAgent` for the current OS (1Password socket path)
  2. `Include`s the shared submodule config
- Never put OS-specific paths (like `IdentityAgent`) in the submodule config

## Package management — `scripts/lib.sh`

Every installable item — tool binaries, stow configs, special handlers — is declared in `manifest.yaml`. Profiles in `profiles/*.yaml` curate which items run on which machine context. See [manifest.md](manifest.md) and [profiles.md](profiles.md) for full schema reference.

The shared library `scripts/lib.sh` provides (yq-backed):
- `detect_pkg_manager()` — returns `arch`, `apt`, or `brew`
- `ensure_yq` — bootstraps yq if missing (brew on Darwin, `install-yq.sh` on Linux)
- `manifest_list_all` — list every item key
- `manifest_resolve_alias <name>` — resolve `op` → `1password-cli`, `nvim` → `neovim`, etc.
- `manifest_kind <item>` — returns `tool` / `config` / `bundle`
- `manifest_field <item> <yq-path>` — generic field read
- `manifest_post_install <item>` — list post_install hook names
- `manifest_requires_met <item>` — check `requires:` predicates against the host
- `manifest_label <item>` — picker label with `(+ config)` suffix for bundles
- `install_tool <item>` / `install_tools <item ...>` — binary installer (manifest-driven)
- `update_source_tools` — rebuild items flagged with `install.update: true`
- `apply_tombstones` — remove paths declared in `tombstones.yaml` (desired absences)
- `ensure_gum()` — bootstraps gum if not installed

Custom config handlers live in `scripts/handlers/*.sh` (`ai.sh`, `cargo.sh`, `linux.sh`, `windows.sh`, `alacritty.sh`, `neovim.sh`) and are referenced by name from `manifest.yaml`. Tool install scripts in `scripts/tools/install-*.sh` are referenced via `install.script` in manifest entries.

## System detection

- Auto-detect OS: `$OSTYPE` (macOS vs Linux)
- Detect Omarchy: `[[ -d "$HOME/.local/share/omarchy" ]]`
- Detect package manager: `detect_pkg_manager()` in `scripts/lib.sh`
- macOS: Homebrew for packages (auto-installed by `install.sh` if missing)
- Arch Linux: pacman/yay for packages
- Debian/Ubuntu: apt + script fallbacks for missing tools

## AI config (`ai/`)

Shared AI agent configuration owned by this dotfiles repo at `~/.dotfiles/ai/`. Grok Build, OpenCode, and Claude Code are peer harnesses: each has its own installer that links or generates straight from `ai/` into its own tree, and none reads another harness's files. For directory layout and how to add skills/agents/rules, see [ai.md](ai.md).

**Which harnesses are configured:** `scripts/lib.sh` holds the registry (`AI_HARNESSES=(claude grok opencode)`, path helpers, `read_active_profile`, `profile_mcp_json`, `profile_ai_default`). `ai_harness_enabled <h>` is true when the active profile lists `<h>` in `items:`, or, with no active profile, when the harness is installed. Every installer and MCP writer returns early for a harness that is not enabled. With an active profile, `dot install`, `install_item`, and the manual picker refuse a harness the profile doesn't list (`ai_harness_allowed`).

**What `install_ai_grok()` does:**
- Symlinks `ai/skills/*`, `ai/agents/*`, and `ai/hooks/*` into `~/.grok/{skills,agents,hooks}/` (Grok registers hooks by filename prefix)
- Flattens `ai/rules/**/*.md` into `~/.grok/rules/<basename>.md`
- Seeds `~/.grok/config.toml` from `grok/.grok/config.toml` only if missing; never overwrites the live file
- Forces `[compat.claude]` off (the Claude installer fills `~/.claude`, so Grok would load everything twice) and `[folder_trust] enabled = false`; merges trusted folders
- Always upserts `grok/.grok/base.toml` into the live file
- If `grok/.grok/overlays/<active-profile>.toml` exists, upserts it after the base (e.g. work Bedrock). Overlays hold Grok-only settings; MCP tables in an overlay are ignored with a warning. Profile wins on conflict; `model.*` overlay tables replace wholesale.
- Symlinks `pager.toml`

**What `install_ai_opencode()` does** (skips until `~/.config/opencode` is stowed; never creates it):
- Links each `ai/skills/<name>` into `~/.config/opencode/skills/` (a real dir inside the stowed, gitignored package dir). OpenCode also reads `~/.claude/skills`; duplicates resolve by precedence to the same files.
- Runs `ai/scripts/generate-opencode-config.sh`, which writes agents (from `ai/agents/*.md`) and `instructions` (paths of `ai/rules/**/*.md`) into `opencode.json` and re-applies `.provider` from `opencode.json.tpl`

**What `install_ai_claude()` does:**
- Symlinks `ai/skills/*` into `~/.claude/skills/` (skipping Claude's reserved `skills/synced`) and `ai/agents/*` into `~/.claude/agents/`; flattens rules into `~/.claude/rules/`
- `ensure_claude_settings` merges the Stop / Notification (permission and elicitation prompts only) / UserPromptSubmit command hooks into `~/.claude/settings.json`
- Sets `attribution` to `{commit: "", pr: "", sessionUrl: false}` in the same file so Claude never adds `Co-Authored-By` trailers, PR bylines, or session links

**Hooks:** scripts live once in `ai/hooks/`; registration is per harness (Grok by filename prefix, Claude via the `settings.json` merge above, OpenCode via the `opencode/.config/opencode/plugins/notify-sound/tui.js` plugin that calls `stop_notify.sh`). Grok's hook payload is camelCase and Claude's is snake_case, so shared scripts read only fields spelled the same in both (e.g. `cwd`).

**Per-env instructions:** `dot agent env link` links `agent-files/env/<name>/AGENTS.md` into each enabled harness's user instructions file. See [dot-agent.md](dot-agent.md).

**Shared MCP:** `generate_mcp_configs()` (post_install on `grok`, `opencode`, and `claude`, or `dot mcp-regen`) — see [Shared MCP configuration](#shared-mcp-configuration).

**`dot update`:** inside the pull block runs `install_ai_<h>` for each enabled harness; after `reconcile_profile` runs `agent_env_refresh` (re-links the current env's targets and skills, drops legacy hops) and `install_ai_tool_default`.

**Default harness:** profile `ai.default` picks the harness for `tav`/`wta`/`wtc` and commit messages. The `ai-tool` core extra and `dot update` write `AI_TOOL` / `AI_TOOL_RESUME` / `AI_TOOL_PIPE` into `~/.localrc` from it only when `~/.localrc` has no `AI_TOOL`. `dot ai-tool [INT] [PIPE]` overrides; its picker lists only enabled harnesses.

**Idempotency:** `clean_ai_symlinks()` runs before every install, removing any symlinks in the target directory that point into `~/.dotfiles/ai/` (or legacy `ecc/`).

**1Password:** `op_inject_multi()` resolves `op://` secret references across multiple 1Password accounts by building a vault-to-account map and using `op read` per-secret (standard `op inject` only supports one account per call).

## Methodologies

### Symlink strategy: merge vs replace

Use `link_file` (symlinks the entire directory) when the directory is exclusively owned by one source. Use per-item links when personal files need to coexist alongside sourced files: `link_ai_entries` in `scripts/handlers/ai.sh` links each `ai/` skill, agent, and hook into a harness's own dir, so personal and env skills sit next to them.

### Dynamic config merging

When two sources contribute to a single config file (e.g., generated AI agents + personal config in `opencode.json`), merge at install time using `jq -s '.[0] * .[1]'` rather than maintaining a combined copy. The base config comes first, personal overrides second (wins on conflicts). This eliminates duplication and keeps each source independently maintainable.

### Shared MCP configuration

MCP servers are defined once in `~/.dotfiles/ai/mcp-servers.json.tpl` (`command`/`args`/`env`/`url` JSON with `op://` secret references; `"default": true` on context7 and firecrawl). The active profile's `mcp:` block is the only source of truth for which servers run: `mcp.enable` picks them (the roster's `default: true` servers when there is no profile or no block) and `mcp.override.<server>` patches launch fields. Overrides apply before 1Password injection and `$HOME` expansion; only enabled servers are resolved, so unused servers' secrets are never fetched or written.

`generate_mcp_configs` writes exactly the enabled set to every enabled harness:
- **Grok** (`write_grok_mcp`): `[mcp_servers.*]` in live `~/.grok/config.toml` via `ai/scripts/merge-grok-mcp.py`, which also removes those names from `[tools] disabled_mcp_servers`
- **OpenCode** (`write_opencode_mcp`): `mcp.servers` in `~/.config/opencode/opencode.json`
- **Claude Code** (`write_claude_mcp`): `mcpServers` in `~/.claude.json`; roster names not enabled are removed, hand-added non-roster servers stay

Hand toggles inside a harness are reset by the next regen. The run is skipped when `~/.cache/dotfiles/mcp-servers.hash` (roster + profile `mcp:` block + harness list) is unchanged; `~/.cache/dotfiles/<harness>-mcp-servers` records the names last written. `dot mcp-regen` forces a run.

### Gitignore for generated symlinks in stowed dirs

When creating symlinks inside a stowed directory (e.g., `~/.config/opencode/commands/`), those symlinks resolve through the stow symlink into the dotfiles git tree and show as unstaged changes. Add them to the package's `.gitignore` to prevent this.

## Tool-specific notes

- **Kubernetes:** configs in `~/.kube/`, use `kcs` (select config), `kca` (load all)
- **fzf:** many functions (`kcs`, `kn`, `kc`, `kl`, `ke`, etc.) use fzf when no args provided
- **1Password:** `opl` function for CLI login, SSH agent for git signing
