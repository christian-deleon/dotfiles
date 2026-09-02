# Dotfiles

Personal dotfiles for macOS, Linux (including [Omarchy](https://omarchy.org/)), and WSL2. Shell configs, dev tools, and app configs managed across machines.

## Install

Clone over HTTPS first — on a fresh machine the 1Password SSH agent isn't set up yet, so SSH cloning would fail:

```bash
git clone https://github.com/christian-deleon/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh          # bare-minimum core, then pickers for everything else
```

After install (1Password + SSH agent now configured), switch the remote to SSH:

```bash
git -C ~/.dotfiles remote set-url origin git@github.com:christian-deleon/dotfiles.git
```

Only the bare minimum runs unconditionally — shell config and the `dot` CLI. Then you pick:

- **A profile** — a curated, hand-authored set of tools + configs for a specific machine context (`omarchy-personal`, `wsl-personal`, `wsl-work`, `macos-personal`, …). Only profiles whose `requires:` predicates pass on the host appear in the picker.
- **Manual selection** — ad-hoc picker of core extras + individual items from `manifest.yaml`. Use this on a brand-new machine type, then author a profile when you're ready to reproduce it elsewhere.

The picker auto-suggests the first compatible profile based on host detection (Hyprland present → omarchy, Darwin → macos, microsoft in `/proc/version` → wsl). On `dot update`, the active profile is reconciled (missing items get installed; profile reconcile is add-only). Residue from *retired* tools is cleaned via [`tombstones.yaml`](tombstones.yaml) — see [docs/tombstones.md](docs/tombstones.md).

If `op` (1Password CLI) is missing, MCP servers that need secrets are skipped automatically; the keyless ones still install.

## `dot` CLI

```bash
dot edit                       # Open dotfiles in $EDITOR
dot update                     # Pull, AI refresh, tombstones, source tools, reconcile profile
dot install                    # Interactive: pick a profile or items manually
dot install <name>...          # Install one or more items directly (binary + config for bundles)
dot profile list               # Show profiles with compatibility / active markers
dot profile show               # Print the currently active profile
dot profile use <name>         # Switch active profile and run reconciliation
dot mcp-regen                  # Regenerate MCP config for Grok (and OpenCode adapter) from ai/mcp-servers.json.tpl
dot agent link [name]          # Symlink per-project AGENTS.md (private overlay submodule)
dot agent unlink               # Remove the per-project symlinks
dot agent list|status|update   # List projects / show cwd state / pull latest agent-files
dot agent env link <name>      # Symlink per-environment AGENTS.md into ~/.grok/ (OpenCode hops)
dot agent env unlink|list|status
dot theme add <url>            # Add an Omarchy theme submodule
dot theme list                 # List installed Omarchy themes
dot theme update               # Pull latest from all theme submodules
dot brew bundle <profile>      # macOS: install Homebrew packages (home/work)
dot brew save <profile>        # macOS: save current Homebrew packages
```

### Agent files (`dot agent`)

Two scopes of overlay agent files, sourced from the private `agent-files` submodule (synced across machines via private GitHub). Content is committed automatically inside the submodule; push to the remote is always manual.

**Per-project — `dot agent link`.** For projects where `AGENTS.md` can't be committed and `.gitignore` can't be modified. Content lives in `agent-files/projects/<project>/AGENTS.md`; the project gets a symlink excluded via the shared `.git/info/exclude`. An untracked leftover `CLAUDE.md` is migrated to `AGENTS.md`. A worktrunk `post-start` hook auto-links every newly created worktree.

**Per-environment — `dot agent env link <name>`.** For machine- or environment-scoped context. Content lives in `agent-files/env/<env>/AGENTS.md` and is symlinked into Grok's `~/.grok/AGENTS.md` (OpenCode hops at the same file). The symlinks themselves are the state. Opt out with `dot agent env unlink`.

## Windows bootstrap

For a fresh Windows machine. `windows/bootstrap.ps1` `winget`-installs Alacritty and JetBrainsMono Nerd Font, drops a Windows-side Alacritty config (`%APPDATA%\alacritty\alacritty.toml`) that auto-launches WSL Ubuntu-26.04 when Alacritty starts, then installs WSL Ubuntu-26.04.

From PowerShell — no admin needed; UAC will prompt if individual steps require it:

```powershell
irm https://raw.githubusercontent.com/christian-deleon/dotfiles/refs/heads/main/windows/bootstrap.ps1 | iex
```

On a brand-new Windows machine where WSL features have to be enabled, the WSL step may need a reboot first. If the script warns about that, **reboot Windows and re-run the same one-liner** — it's safe to run twice (winget steps are idempotent, and `wsl --install` resumes correctly after the reboot).

After Ubuntu-26.04 is installed, launch the Ubuntu app from the Start menu, finish the first-time user setup, then inside Ubuntu:

```bash
git clone https://github.com/christian-deleon/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && ./install.sh
# After install, switch to SSH:
git -C ~/.dotfiles remote set-url origin git@github.com:christian-deleon/dotfiles.git
```

## App Configs

App configs (`~/.config/`) are mostly managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot). Stow packages must be **declared in `manifest.yaml`** (`config.type: stow`) — the installer does not auto-discover them from the filesystem. Profiles (or `dot install <name>`) select which items to install.

`hypr` and `omarchy` are the exception: Omarchy owns `~/.config/hypr` and `~/.config/omarchy`. This repo only copies personal overlays in (see [docs/architecture.md](docs/architecture.md)). Do not `omadot put hypr` or `omadot put omarchy`.

**New config from scratch** — write files into the repo, add a manifest entry, then stow:

```bash
mkdir -p <package>/.config/<package>/
# ...edit files in <package>/.config/<package>/...
# add <package> to manifest.yaml with config.type: stow (and to profiles as needed)
omadot put <package>     # creates symlink ~/.config/<package> -> ~/.dotfiles/<package>/.config/<package>
git add <package> manifest.yaml profiles/ && git commit
```

**Importing an existing `~/.config/<package>/`** into the repo:

```bash
omadot get <package>     # copy ~/.config/<package> into the repo
omadot put <package>     # replace original with symlink to dotfiles
# add manifest + profile entries if this is a new item
git add <package> manifest.yaml profiles/ && git commit
```

Stale `~/.config/<pkg>` symlinks from packages that have since been dropped are cleaned automatically on every `./install.sh`, `dot install`, and `dot update`. Non-stow residue (script installs, XDG data/cache, home files) is declared in `tombstones.yaml` and removed by the same entry points.

## AI Config

Shared AI agent configuration for **Grok Build TUI** lives in `ai/` (plus `grok/.grok/` for native seed files). **OpenCode** is a second-class adapter.

Select `grok` or `opencode` from `dot install`:

- **Grok Build TUI** — skills/agents/hooks/rules linked into `~/.grok/`; pager.toml; config.toml seeded if missing; optional `grok/.grok/overlays/<profile>.toml` merged on matching machines; folder-trust grants merged; MCP written as `[mcp_servers.*]`
- **OpenCode** — `skills` and `AGENTS.md` hop at Grok's live tree; agents/instructions/MCP generated into `opencode.json`
- **MCP servers** — defined once in `ai/mcp-servers.json.tpl`. 1Password secrets are injected; unresolved `op://` refs are dropped. Use `dot mcp-regen` to force re-injection.

`dot update` refreshes Grok and the OpenCode adapter. See [docs/ai.md](docs/ai.md).

## Manifest and Profiles

Every item the repo knows about — tools, configs, bundles, handlers — is declared in `manifest.yaml`. Profiles in `profiles/*.yaml` curate which items run on which machine context. See [docs/manifest.md](docs/manifest.md) and [docs/profiles.md](docs/profiles.md).

## Docs

- [Architecture](docs/architecture.md) — installer flow, stow, SSH, AI plumbing
- [Common operations](docs/common-operations.md) — add aliases, functions, manifest items, configs
- [Manifest schema](docs/manifest.md) — the universal inventory of items
- [Profiles](docs/profiles.md) — curated per-machine install sets
- [Tombstones](docs/tombstones.md) — desired-state absences for retired tools
- [AI config](docs/ai.md) — skills, agents, rules, MCP (Grok first-class; OpenCode adapter)
- [Dot agent overlays](docs/dot-agent.md) — per-project and per-env AGENTS.md via `dot agent`
- [Functions reference](docs/functions.md)
- [Aliases reference](docs/aliases.md)
- [Shell style](docs/shell-style.md) — bash conventions for this repo
- [Windows bootstrap](docs/windows-bootstrap.md) — `windows/bootstrap.ps1`

## License

This project is open source and available under the [MIT License](LICENSE).
