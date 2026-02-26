# Agent Guidelines for Dotfiles Repository

Guidelines for AI coding agents working in this personal dotfiles repository. This repository manages shell configurations, development tool setups, Omarchy desktop configs, and system bootstrapping scripts for macOS and Linux (including Omarchy/Arch Linux).

## Repository Overview

**Location:** `~/.dotfiles/`

**Primary Languages:** Shell (Bash), YAML (packages.yaml), Configuration files

**Key Components:**

- Shell configs: `.commonrc` (cross-platform), `.zshrc` (macOS with Oh My Zsh + Powerlevel10k), `.bashrc` (reference only)
- Dev tool configs: git, tmux
- Omarchy desktop configs: hypr, waybar, alacritty, kitty, ghostty, mako, walker, btop, fastfetch, lazygit, omarchy, opencode (managed via GNU Stow + omadot)
- Package management: `packages.yaml` + `tools/lib.sh` (cross-platform), Homebrew Brewfile profiles (macOS)
- Custom aliases, functions (many with fzf integration), shell utilities
- Documentation: `docs/functions.md`, `docs/aliases.md`

## Architecture

**"Source into, never replace."** The system (Omarchy, Ubuntu, macOS) owns `~/.bashrc`. Dotfiles provide customizations via `~/.commonrc` which is sourced into the system's shell config.

```
SYSTEM-OWNED (never symlinked)          DOTFILES (symlinked from ~/.dotfiles/)
─────────────────────────────           ──────────────────────────────────────
~/.bashrc (Omarchy / Ubuntu / etc.)     ~/.commonrc ─┬─ ~/.aliases
  └── source ~/.commonrc                             ├── ~/.functions
                                                     └── ~/.localrc (not tracked)
~/.zshrc (macOS, symlinked)
  └── source ~/.commonrc
```

**Key principle:** `.bashrc` is never symlinked. `install.sh` injects `source ~/.commonrc` into the system's existing `~/.bashrc`. Machine-specific config (`EDITOR`, secrets, env vars) goes in `~/.localrc` (not tracked).

### Machine Profiles

The installer supports three profiles, auto-detected at startup:

| Profile | Detection | Modules |
|---------|-----------|---------|
| `omarchy` | `~/.local/share/omarchy` exists | Shell, Git, SSH, Tmux, Dot CLI, Omarchy config (stow) |
| `mac-home` | macOS + user choice | Shell, Zsh, Git, SSH, Tmux, Dot CLI |
| `mac-work` | macOS + user choice | Shell, Zsh, Git, SSH, Tmux, Dot CLI |

Profile can be forced with `--profile=omarchy|mac-home|mac-work`.

### Omarchy Config Management (Stow + omadot)

On Omarchy machines, desktop configs in `~/.config/` are managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot):

- Configs are stored as stow packages in `~/.dotfiles/<pkg>/.config/<pkg>/`
- `omadot put <pkg>` creates directory-level symlinks: `~/.config/<pkg>` -> `~/.dotfiles/<pkg>/.config/<pkg>`
- New files in `~/.config/<pkg>/` automatically appear in the repo (no re-run needed)
- `install.sh` auto-installs stow + omadot and runs `omadot put` for each package

**Stow packages** (defined in `OMARCHY_STOW_PACKAGES` in `install.sh`):
```
hypr  waybar  alacritty  walker  kitty  ghostty  mako  btop  fastfetch  lazygit  omarchy  opencode
```

**Not managed by omadot** (Omarchy-owned): `starship.toml`, `~/.config/git/`

**IMPORTANT:** Never use `omadot put --all` in this repo. It would try to stow non-package directories (brew/, tools/, docs/, etc.). Always use the explicit package list or `install_omarchy_config()`.

### Omarchy Compatibility

On [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland):

- Omarchy owns `~/.bashrc` and sources its defaults (starship, mise, zoxide, eza, etc.)
- Dotfiles layer on top via `.commonrc` — never replace Omarchy's shell setup
- Omarchy owns `~/.config/starship.toml` — dotfiles do not manage starship config
- 1Password SSH agent path: `/opt/1Password/op-ssh-sign` (Linux) vs `/Applications/1Password.app/Contents/MacOS/op-ssh-sign` (macOS)
- 1Password SSH socket: `~/.1password/agent.sock` (Linux) vs `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` (macOS)

### SSH Config

- `.ssh/` is a git submodule containing shared host entries (no OS-specific settings)
- `~/.ssh/config` is NOT a symlink — it's a generated file created by `install.sh` that:
  1. Sets the correct `IdentityAgent` for the current OS (1Password socket path)
  2. `Include`s the shared submodule config
- Never put OS-specific paths (like `IdentityAgent`) in the submodule config

### Package Management (`packages.yaml` + `tools/`)

Tools are defined in `packages.yaml` with per-OS package names and optional script fallbacks:

```yaml
kubectl:
  description: Kubernetes CLI
  arch: kubectl          # pacman/yay package name
  apt: null              # null = no native package, use script
  brew: kubectl          # Homebrew formula
  script: tools/install-kubectl.sh  # fallback installer
```

The shared library `tools/lib.sh` provides:
- `detect_pkg_manager()` — returns `arch`, `apt`, or `brew`
- `list_tools()` — lists all tool names from `packages.yaml`
- `get_tool_field <tool> <field>` — minimal YAML parser (no yq dependency at bootstrap)
- `install_tool <tool>` — checks if installed -> tries OS package manager -> falls back to script
- `install_tools <tool ...>` — installs multiple tools with gum spinner support
- `ensure_gum()` — bootstraps gum if not installed

Install scripts in `tools/install-*.sh` are fallbacks for systems where the tool isn't available as a native package. They use official install methods (curl binaries, APT repos, etc.).

## Build/Test/Run Commands

### Testing & Validation

```bash
# Test single shell script syntax
bash -n .functions

# Debug single script
bash -x install.sh

# Test single function
source .functions && kcs

# Syntax-check all tool install scripts
for f in tools/*.sh; do bash -n "$f"; done

# Test all shell files
for f in .[a-z]*; do [[ -f "$f" ]] && bash -n "$f" 2>&1 | grep -v "cannot execute" || true; done
```

### Installation & Management

```bash
./install.sh                          # Interactive with auto-detected profile
./install.sh --all                    # Install everything (auto-detect profile)
./install.sh --profile=omarchy --all  # Force profile
./install.sh --help                   # Show available modules and tools
dot edit                              # Open dotfiles in editor ($EDITOR)
dot update                            # Update system packages and dotfiles
dot install                           # Interactive tool picker (gum choose)
dot install docker kubectl            # Install specific tools by name
```

### Homebrew (macOS only)

```bash
dot brew-install          # Install Homebrew
dot brew-bundle <profile> # Install from profile (home, work)
dot brew-save <profile>   # Save current packages to profile
```

### Omadot (Omarchy only)

```bash
omadot get <pkg>          # Capture config from ~/.config/ into ~/.dotfiles/
omadot put <pkg>          # Stow config back (create symlink)
omadot list               # List managed packages
```

## Code Style Guidelines

### Shell Script Standards

**Output:** Use `printf '%b\n'` instead of `echo -e` for escape sequence interpretation (portability).

**File Structure:**

```bash
#!/bin/bash
# Optional description

set -e  # Exit on error for critical scripts

# Document functions with comments
# Description of what the function does
function my_function() {
    local arg="$1"
    # Implementation
}
```

**Variables:**

- UPPERCASE for environment variables/constants: `DOTFILES_DIR`, `KUBECONFIG`
- lowercase for local variables: `local file`, `local namespace`
- Always quote: `"$variable"` not `$variable`
- Use `local` keyword in functions

**Conditionals:**

- Use `[[ ]]` not `[ ]`: `if [[ -f "$file" ]]; then`
- Pattern matching: `if [[ "$var" =~ ^pattern ]]; then`
- Command checks: `if command -v cmd &>/dev/null; then`

**OS Detection:**

```bash
# Prefer $OSTYPE for OS detection
if [[ "$OSTYPE" == darwin* ]]; then
    # macOS
else
    # Linux
fi

# Check for Omarchy
if [[ -d "$HOME/.local/share/omarchy" ]]; then
    # Omarchy-specific
fi
```

**Error Handling:**

```bash
# Exit on error for critical scripts
set -e

# Check required arguments
if [[ -z "$1" ]]; then
    echo "Error: Missing required argument"
    return 1
fi
```

### Naming Conventions

**Files:**

- Dotfiles: `.filename` (`.commonrc`, `.aliases`, `.functions`)
- Scripts: `lowercase-with-hyphens.sh` (`install.sh`)
- Install scripts: `tools/install-<tool>.sh` (`tools/install-kubectl.sh`)
- Brewfiles: `Brewfile-profile` (`Brewfile-home`)

**Functions:**

- Descriptive names: `update_system()`, `install_tool()`
- Kubernetes prefix: `k*` (`kcs`, `kn`, `kl`, `ke`, `kdp`)
- Git prefix: `g*` (`gc`, `gaw`, `grw`, `gcbare`)
- Many support fzf when called without arguments

**Aliases:**

- Short: `k` (kubectl), `tf` (terraform), `dc` (docker compose)
- Consistent prefixes: `kp*` (pods), `kd*` (deployments), `f*` (flux)

### YAML (packages.yaml)

```yaml
tool-name:
  description: Short description
  arch: pacman-package-name
  apt: apt-package-name     # null if not available
  brew: homebrew-formula
  script: tools/install-tool.sh  # optional fallback
```

**Indentation:** 2 spaces (YAML), 4 spaces (Shell)

## Documentation Requirements

**Always update when making changes:**

1. **README.md** - configurations, tools, structure, features
2. **docs/functions.md** - new/modified functions with examples
3. **docs/aliases.md** - new/modified aliases
4. **AGENTS.md** - if architecture, file structure, or conventions change

**Standards:**

- Clear headings and structure
- Practical examples for complex functions
- Simple, direct language
- Document macOS vs Linux differences
- Update Quick Start if installation changes

**File-level comments:**

```bash
# Description of function purpose (can span multiple lines)
function my_function() {
    local arg="$1"
    # Implementation
}
```

## Project-Specific Notes

### System Detection & Packages

- Auto-detect OS: `$OSTYPE` (macOS vs Linux)
- Detect Omarchy: `[[ -d "$HOME/.local/share/omarchy" ]]`
- Detect package manager: `detect_pkg_manager()` in `tools/lib.sh`
- macOS: Homebrew for packages (auto-installed by `install.sh` if missing)
- Arch Linux: pacman/yay for packages
- Debian/Ubuntu: apt + script fallbacks for missing tools

### Files Symlinked to $HOME

| File | Notes |
|------|-------|
| `.commonrc` | Core config — sourced by both bash and zsh |
| `.aliases` | Personal aliases |
| `.functions` | Personal functions (fzf-powered kubectl, git worktrees) |
| `.zshrc` | macOS zsh config (Oh My Zsh + Powerlevel10k) |
| `.p10k.zsh` | Powerlevel10k prompt config (macOS) |
| `.tmux.conf` | Tmux configuration |
| `.gitconfig.dotfiles` -> `~/.gitconfig` | Shared git config |

### Omadot Stow Packages (Omarchy only)

| Package | Config location | Notes |
|---------|----------------|-------|
| `hypr` | `~/.config/hypr/` | Hyprland WM (bindings, monitors, look-n-feel) |
| `waybar` | `~/.config/waybar/` | Status bar layout and styling |
| `alacritty` | `~/.config/alacritty/` | Alacritty terminal |
| `kitty` | `~/.config/kitty/` | Kitty terminal |
| `ghostty` | `~/.config/ghostty/` | Ghostty terminal |
| `walker` | `~/.config/walker/` | App launcher |
| `mako` | `~/.config/mako/` | Notifications |
| `btop` | `~/.config/btop/` | System monitor |
| `fastfetch` | `~/.config/fastfetch/` | System info display |
| `lazygit` | `~/.config/lazygit/` | Lazygit TUI |
| `omarchy` | `~/.config/omarchy/` | Themes, hooks, extensions |
| `opencode` | `~/.config/opencode/` | OpenCode AI agent config and plugins |

### Files NOT Symlinked (reference or generated)

| File | Notes |
|------|-------|
| `.bashrc` | Reference for non-managed systems — never symlinked |
| `~/.ssh/config` | Generated by `install.sh` — not a symlink |

### Directories (contents symlinked one level deep)

| Dir | Notes |
|-----|-------|
| `.tmux/` | tpm plugin manager (git submodule) |

### Not Tracked (machine-specific)

| File | Purpose |
|------|---------|
| `~/.localrc` | Machine-specific config (EDITOR, secrets, env vars) |
| `~/.gitconfig.local` | Personal git identity (name, email, signing key) |

### Shell Loading Order

**On Omarchy/Linux (bash):**

1. Omarchy's `~/.bashrc` -> sources Omarchy defaults (starship, mise, zoxide, etc.)
2. `~/.bashrc` -> sources `~/.commonrc` (injected by install.sh)
3. `.commonrc` -> sources `.aliases`, `.functions`, `.localrc`

**On macOS (zsh):**

1. `.zshrc` -> Homebrew, Oh My Zsh, Powerlevel10k, zsh plugins
2. `.zshrc` -> sources `.commonrc`
3. `.commonrc` -> sources `.aliases`, `.functions`, `.localrc`
4. `.zshrc` -> fzf, `.p10k.zsh`

### Tool-Specific

- Kubernetes: configs in `~/.kube/`, use `kcs` (select config), `kca` (load all)
- fzf: Many functions (`kcs`, `kn`, `kc`, `kl`, `ke`, etc.) use fzf when no args provided
- 1Password: `opl` function for CLI login, SSH agent for git signing

## Common Operations

### Adding New Aliases

1. Add to `.aliases` file, group with related (Kubernetes, Git, Docker)
2. Use consistent prefixing (e.g., `k*` for kubectl, `f*` for flux)
3. Check for conflicts with functions in `.functions` (e.g., don't alias `sk` if `sk()` function exists)
4. Update `docs/aliases.md`
5. Update README.md if significant

### Adding New Functions

1. Add to `.functions` with comment above
2. Group by category (General, Kubernetes, Git, etc.)
3. Consider fzf integration for interactive selection
4. Update `docs/functions.md` with examples
5. `dot` CLI auto-parses documented functions
6. Update README.md for major utilities

### Adding a New Tool to packages.yaml

1. Add entry to `packages.yaml` with description and per-OS package names
2. Use `null` for OS package managers that don't have the tool
3. If needed, create `tools/install-<tool>.sh` as a fallback script
4. Test: `dot install <tool>`
5. Update README.md tool list

### Adding a New Omarchy Config to omadot

1. Run `omadot get <package>` to capture from `~/.config/`
2. Verify the stow package exists: `ls ~/.dotfiles/<package>/.config/<package>/`
3. Add the package name to `OMARCHY_STOW_PACKAGES` in `install.sh`
4. Update AGENTS.md stow packages table
5. `git add ~/.dotfiles/<package> && git commit`

### Modifying install.sh

1. **Profiles**: Detected by `detect_profile()`, modules filtered by `build_module_list()` using `ALL_MODULE_PROFILES` flags (`o`=omarchy, `m`=mac)
2. **Phase 1** (config): Modules in `ALL_MODULES` / `ALL_MODULE_LABELS` / `ALL_MODULE_PROFILES` parallel arrays, each with an `install_<module_name>` function
3. **Phase 2** (tools): Uses `tools/lib.sh` and `packages.yaml` — gum choose for interactive selection
4. **Prerequisites**: `ensure_homebrew()`, `ensure_stow()`, `ensure_omadot()` auto-install if missing
5. **Idempotency**: All modules must be safe to re-run. Use `ln -snf` for symlinks, check before stowing, skip if already done
6. OS-specific paths must use `$OSTYPE` detection
7. Never replace `~/.bashrc` — only inject source line
8. SSH config is generated (not symlinked) with OS-appropriate `IdentityAgent`
9. Test with `bash -n install.sh` and `./install.sh --help`

### Modifying dot.sh

1. Sources `tools/lib.sh` for package management
2. `dot install` with no args shows gum interactive picker
3. `dot install <tool> [tool ...]` installs specific tools directly
4. `dot update` handles OS-appropriate package updates (pacman/yay, apt, brew)
5. Keep brew commands as-is (macOS only)

### Modifying .commonrc

1. Keep it thin — only cross-platform config belongs here
2. Guard all sources: `[[ -f "$file" ]] && source "$file"`
3. Use shell detection for completions: `[[ -n "$BASH_VERSION" ]]` / `[[ -n "$ZSH_VERSION" ]]`
4. Don't duplicate what Omarchy already provides (starship, mise, zoxide, history, bash-completion)
5. Don't duplicate what `.zshrc` already provides (Homebrew, Oh My Zsh, p10k)

## Testing Checklist

Before committing:

- [ ] `bash -n <script>` - shell syntax check
- [ ] `for f in tools/*.sh; do bash -n "$f"; done` - check all install scripts
- [ ] `source .functions && <function-name>` - test functions work
- [ ] Aliases work in new shell session
- [ ] Documentation updated (`README.md`, `docs/functions.md`, `docs/aliases.md`)
- [ ] No hardcoded personal info (use `.gitconfig.local`, `.localrc`)
- [ ] No hardcoded OS-specific paths (use `$OSTYPE` detection)
- [ ] Works on target system (macOS/Linux/Omarchy)
- [ ] `install.sh` modules work correctly
- [ ] Omadot stow packages are correctly listed in `OMARCHY_STOW_PACKAGES`

## Important Reminders

- **Personal repo** - changes reflect personal preferences
- **Source into, never replace** - never symlink `.bashrc`; inject `source ~/.commonrc`
- **Backup first** - `install.sh` auto-backs up to `~/dotfiles_backup`
- **Test before push** - validate in safe environment
- **Document everything** - keep docs comprehensive and current
- **OS-aware** - use `$OSTYPE` for macOS vs Linux paths (1Password, Homebrew, etc.)
- **Omarchy-aware** - don't duplicate or conflict with Omarchy's shell defaults
- **Stow-aware** - never use `omadot put --all`; always use the explicit package list
- **Idempotent** - all install modules must be safe to re-run
- **Privacy** - never commit secrets, tokens, credentials
- **fzf integration** - many kubectl/git functions support interactive mode

---

For details: [README.md](README.md) | [docs/functions.md](docs/functions.md) | [docs/aliases.md](docs/aliases.md)
