# Dotfiles

Personal dotfiles for macOS, Linux (including [Omarchy](https://omarchy.org/)), and WSL2. Shell configs, dev tools, and app configs managed across machines.

## Install

```bash
git clone git@github.com:christian-deleon/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh          # bare-minimum core, then pickers for everything else
```

Only the bare minimum runs unconditionally — shell config and the `dot` CLI. Everything else is opt-in/opt-out via interactive pickers, so you can install just what you need on each machine (e.g. skip SSH config and 1Password-dependent MCP servers on a locked-down work box):

1. **Core extras** — `git-submodules`, `git-config`, `ssh-config`, `zsh-config` (macOS), `omarchy-themes` (Omarchy), `default-terminal` (Omarchy — sets Alacritty as the default terminal). All pre-selected by default; deselect what you don't want.
2. **App configs** — stow packages + tmux + claude.
3. **Dev tools** — anything in `packages.yaml`. Failed individual tool installs are reported but don't abort the rest.

If `op` (1Password CLI) is missing, MCP servers that need secrets are skipped automatically; the keyless ones still install.

## `dot` CLI

```bash
dot edit                       # Open dotfiles in $EDITOR
dot update                     # Update system packages, dotfiles, submodules, and AI config
dot install                    # Interactive picker for app configs and dev tools
dot install <tool>...          # Install specific tool(s) from packages.yaml directly
dot mcp-regen                  # Regenerate MCP config for Claude, OpenCode, and Grok from ai/mcp-servers.json.tpl
dot agent link [name]          # Symlink per-project AGENTS.md/CLAUDE.md (private overlay submodule)
dot agent unlink               # Remove the per-project symlinks
dot agent list|status|update   # List projects / show cwd state / pull latest agent-files
dot agent env link <name>      # Symlink per-environment AGENTS.md into ~/.claude/ and ~/.config/opencode/
dot agent env unlink|list|status
dot theme add <url>            # Add an Omarchy theme submodule
dot theme list                 # List installed Omarchy themes
dot theme update               # Pull latest from all theme submodules
dot brew bundle <profile>      # macOS: install Homebrew packages (home/work)
dot brew save <profile>        # macOS: save current Homebrew packages
```

### Agent files (`dot agent`)

Two scopes of overlay agent files, sourced from the private `agent-files` submodule (synced across machines via private GitHub). Content is committed automatically inside the submodule; push to the remote is always manual.

**Per-project — `dot agent link`.** For projects where `AGENTS.md` / `CLAUDE.md` can't be committed and `.gitignore` can't be modified. Content lives in `agent-files/projects/<project>/AGENTS.md`; the project gets symlinks excluded via the shared `.git/info/exclude`. `dot agent link` symlinks `AGENTS.md` → the canonical source and `CLAUDE.md` → `AGENTS.md` in every worktree. An untracked `AGENTS.md` / `CLAUDE.md` sitting in the project is auto-migrated into the submodule. A worktrunk `post-start` hook auto-links every newly created worktree.

**Per-environment — `dot agent env link <name>`.** For machine- or environment-scoped context (e.g. "this is a locked-down WSL VM behind a corp proxy, X tool is unavailable"). Content lives in `agent-files/env/<env>/AGENTS.md` and is symlinked from one source into every AI tool's global config path (`~/.claude/CLAUDE.md`, `~/.config/opencode/AGENTS.md`). The symlinks themselves are the state — no marker files. Opt out with `dot agent env unlink`.

## Windows bootstrap

For a fresh Windows machine. `windows/bootstrap.ps1` `winget`-installs Alacritty and JetBrainsMono Nerd Font, drops a Windows-side Alacritty config (`%APPDATA%\alacritty\alacritty.toml`) that auto-launches WSL Ubuntu-26.04 when Alacritty starts, then installs WSL Ubuntu-26.04.

From PowerShell — no admin needed; UAC will prompt if individual steps require it:

```powershell
irm https://raw.githubusercontent.com/christian-deleon/dotfiles/refs/heads/main/windows/bootstrap.ps1 | iex
```

On a brand-new Windows machine where WSL features have to be enabled, the WSL step may need a reboot first. If the script warns about that, **reboot Windows and re-run the same one-liner** — it's safe to run twice (winget steps are idempotent, and `wsl --install` resumes correctly after the reboot).

After Ubuntu-26.04 is installed, launch the Ubuntu app from the Start menu, finish the first-time user setup, then inside Ubuntu:

```bash
git clone git@github.com:christian-deleon/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && ./install.sh
```

## App Configs

App configs (`~/.config/`) are managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot) on all platforms. The installer auto-discovers stow packages (any `<pkg>/.config/<pkg>/` directory or single-file `<pkg>/.config/<pkg>.<ext>`) and presents a picker.

**New config from scratch** — write files into the repo first, then stow:

```bash
mkdir -p <package>/.config/<package>/
# ...edit files in <package>/.config/<package>/...
omadot put <package>     # creates symlink ~/.config/<package> -> ~/.dotfiles/<package>/.config/<package>
git add <package> && git commit
```

**Importing an existing `~/.config/<package>/`** into the repo:

```bash
omadot get <package>     # copy ~/.config/<package> into the repo
omadot put <package>     # replace original with symlink to dotfiles
git add <package> && git commit
```

Stale `~/.config/<pkg>` symlinks from packages that have since been dropped are cleaned automatically on every `./install.sh`, `dot install`, and `dot update`.

## AI Config

Shared AI agent configuration for **Claude Code**, **OpenCode**, and **Grok Build TUI** lives in `ai/` (plus `grok/.grok/` for native Grok config files).

Select `claude`, `opencode`, or `grok` from `dot install`:

- **Claude Code** — agents, commands, skills, and rules symlinked into `~/.claude/`
- **OpenCode** — commands and skills symlinked into `~/.config/opencode/`; agents converted from markdown to JSON
- **Grok Build TUI** — skills/agents/hooks symlinked into native `~/.grok/skills/`, `~/.grok/agents/`, `~/.grok/hooks/`; plus `config.toml` + `pager.toml`
- **MCP servers** — defined once in `ai/mcp-servers.json.tpl`, generated into `~/.claude.json` (consumed by Claude Code + Grok via compatibility layer) and `opencode.json`. 1Password secrets are injected; unresolved `op://` refs are dropped gracefully. Use `dot mcp-regen` to force re-injection.

`dot update` refreshes AI config for all three platforms automatically. See [docs/ai.md](docs/ai.md) for details on adding agents, commands, skills, and rules.

## Dev Tools

Tools are defined in `packages.yaml` with per-OS package names. The system auto-detects your package manager (pacman/yay, apt, brew) and falls back to install scripts in `scripts/` when needed.

## Docs

- [Functions reference](docs/functions.md)
- [Aliases reference](docs/aliases.md)

## License

This project is open source and available under the [MIT License](LICENSE).
