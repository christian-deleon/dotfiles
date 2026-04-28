# Dotfiles

Personal dotfiles for macOS, Linux (including [Omarchy](https://omarchy.org/)), and WSL2. Shell configs, dev tools, and app configs managed across machines.

## Install

```bash
git clone git@github.com:christian-deleon/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh          # bare-minimum core, then pickers for everything else
```

Only the bare minimum runs unconditionally — shell config and the `dot` CLI. Everything else is opt-in/opt-out via interactive pickers, so you can install just what you need on each machine (e.g. skip SSH config and 1Password-dependent MCP servers on a locked-down work box):

1. **Core extras** — `git-submodules`, `git-config`, `ssh-config`, `zsh-config` (macOS), `omarchy-themes` (Omarchy). All pre-selected by default; deselect what you don't want.
2. **App configs** — stow packages + tmux + claude.
3. **Dev tools** — anything in `packages.yaml`. Failed individual tool installs are reported but don't abort the rest.

If `op` (1Password CLI) is missing, MCP servers that need secrets are skipped automatically; the keyless ones still install.

## `dot` CLI

```bash
dot edit                  # Open dotfiles in $EDITOR
dot update                # Update system packages, dotfiles, and submodules
dot install               # Interactive picker for app configs and dev tools
dot agent link [name]     # Symlink per-project AGENTS.md/CLAUDE.md (private overlay submodule)
dot agent unlink          # Remove the symlinks
dot theme add <url>       # Add an Omarchy theme submodule
dot theme list            # List installed Omarchy themes
dot brew bundle <profile> # Install Homebrew packages (home/work)
dot brew save <profile>   # Save current Homebrew packages
```

### Per-project agent files

For projects where `AGENTS.md` / `CLAUDE.md` can't be committed and `.gitignore` can't be modified. The actual content lives in a private `agent-files/<project>/` submodule (synced across machines via private GitHub); the project gets symlinks excluded via the shared `.git/info/exclude`.

`dot agent link` symlinks `AGENTS.md` → `agent-files/<project>/AGENTS.md` and `CLAUDE.md` → `AGENTS.md` in every worktree. If you have an untracked `AGENTS.md` or `CLAUDE.md` sitting in the project, it's auto-migrated into the submodule (with `CLAUDE.md` renamed to `AGENTS.md` as canonical) and committed there. Push to the agent-files remote is always manual. A worktrunk `post-start` hook auto-links every newly created worktree.

## App Configs

App configs (`~/.config/`) are managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot) on all platforms. The installer auto-discovers stow packages and presents a picker.

To add a new config:

```bash
omadot get <package>     # capture ~/.config/<package> into the repo
omadot put <package>     # replace original with symlink to dotfiles
git add <package> && git commit
```

`get` copies files into the repo. `put` swaps the original directory for a symlink so changes are tracked. Both steps are needed.

## AI Config

Shared AI agent configuration for Claude Code and OpenCode lives in `ai/`. Select `claude` or `opencode` from `dot install` to symlink agents, commands, skills, and rules into the respective platform directories.

- **Claude Code** — agents, commands, skills, and rules symlinked into `~/.claude/`
- **OpenCode** — commands and skills symlinked into `~/.config/opencode/`; agents converted from markdown to JSON via `ai/scripts/generate-opencode-config.sh`

`dot update` refreshes AI config for both platforms automatically. See [docs/ai.md](docs/ai.md) for details on adding agents, commands, skills, and rules.

## Dev Tools

Tools are defined in `packages.yaml` with per-OS package names. The system auto-detects your package manager (pacman/yay, apt, brew) and falls back to install scripts in `scripts/` when needed.

## Docs

- [Functions reference](docs/functions.md)
- [Aliases reference](docs/aliases.md)

## License

This project is open source and available under the [MIT License](LICENSE).
