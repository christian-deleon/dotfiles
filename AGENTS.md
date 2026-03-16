# Agent Guidelines for Dotfiles Repository

Guidelines for AI coding agents working in this personal dotfiles repository. This repository manages shell configurations, development tool setups, Omarchy desktop configs, and system bootstrapping scripts for macOS and Linux (including Omarchy/Arch Linux).

## Repository Overview

**Location:** `~/.dotfiles/`

**Primary Languages:** Shell (Bash), YAML (packages.yaml), Configuration files

**Key Components:**

- Shell configs: `.commonrc` (cross-platform), `.zshrc` (macOS with Oh My Zsh + Powerlevel10k), `.bashrc` (reference only)
- Dev tool configs: git, tmux
- Omarchy desktop configs: hypr, waybar, kitty, ghostty, mako, walker, btop, fastfetch, lazygit, omarchy, opencode (managed via GNU Stow + omadot)
- AI config: `ai/` directory with agents, commands, skills, and rules for Claude Code and OpenCode
- MCP servers: `ai/mcp-servers.json.tpl` — shared config for Claude Code and OpenCode (with `op://` secret refs)
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

### Installer Flow

There are no profiles or flags. The installer is always interactive:

1. **Core config** runs automatically (shell, git submodules, ssh, git config, dot CLI)
2. **Zsh config** runs automatically on macOS (`$OSTYPE == darwin*`)
3. **App configs picker** — gum multi-select of auto-discovered stow packages + tmux + claude (sorted alphabetically with descriptions)
4. **Dev tools picker** — gum multi-select from `packages.yaml` (sorted alphabetically with descriptions)

### App Config Management (Stow + omadot)

App configs in `~/.config/` are managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot) on all platforms:

- Configs are stored as stow packages in `~/.dotfiles/<pkg>/.config/<pkg>/`
- `omadot put <pkg>` creates directory-level symlinks: `~/.config/<pkg>` -> `~/.dotfiles/<pkg>/.config/<pkg>`
- New files in `~/.config/<pkg>/` automatically appear in the repo (no re-run needed)
- `install.sh` auto-discovers stow packages and presents an interactive picker

**Stow packages** (auto-discovered from repo — any dir with `.config/<name>/` inside; list may change as packages are added/removed):
```
btop  fastfetch  ghostty  hypr  k9s  kitty  lazygit  mako  nvim  omarchy  opencode  walker  waybar  worktrunk
```

**Special packages** (not stow-based, handled by custom install functions):
- `claude` — Claude Code AI config from `ai/` directory (agents, skills, commands, rules)
- `tmux` — direct symlinks for `.tmux.conf` and `.tmux/`

**Not managed by omadot** (Omarchy-owned): `starship.toml`, `~/.config/git/`

**IMPORTANT:** Never use `omadot put --all` in this repo. It would try to stow non-package directories (brew/, tools/, docs/, etc.). The installer auto-discovers valid packages by checking for `<dir>/.config/<dir>/` structure.

### Omarchy Compatibility

On [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland):

- Omarchy owns `~/.bashrc` and sources its defaults (starship, mise, zoxide, eza, etc.)
- Dotfiles layer on top via `.commonrc` — never replace Omarchy's shell setup
- Omarchy owns `~/.config/starship.toml` — dotfiles do not manage starship config
- 1Password SSH agent path: `/opt/1Password/op-ssh-sign` (Linux) vs `/Applications/1Password.app/Contents/MacOS/op-ssh-sign` (macOS)
- 1Password SSH socket: `~/.1password/agent.sock` (Linux) vs `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` (macOS)

### Git Submodules

| Submodule | Path | Branch | Purpose |
|-----------|------|--------|---------|
| tpm | `.tmux/plugins/tpm` | default | Tmux plugin manager |
| ssh-config | `.ssh` | main | Shared SSH host entries |
| omarchy themes | `omarchy/.config/omarchy/themes/*` | default | Omarchy theme submodules |

Submodules are initialized by `install_git_submodules()` during core config. `dot update` runs `git submodule update --remote --init` to pull latest from all remotes.

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
./install.sh                          # Interactive install
./install.sh --help                   # Show available modules and tools
dot edit                              # Open dotfiles in editor ($EDITOR)
dot update                            # Update system packages, dotfiles, submodules, and AI config
dot install                           # Interactive picker for app configs and dev tools (gum choose)
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
- Git prefix: `g*` (`gc`, `gcb`)
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

### Omadot Stow Packages

| Package | Config location | Notes |
|---------|----------------|-------|
| `btop` | `~/.config/btop/` | System monitor |
| `fastfetch` | `~/.config/fastfetch/` | System info display |
| `ghostty` | `~/.config/ghostty/` | Ghostty terminal |
| `hypr` | `~/.config/hypr/` | Hyprland WM (bindings, monitors, look-n-feel) |
| `kitty` | `~/.config/kitty/` | Kitty terminal |
| `lazygit` | `~/.config/lazygit/` | Lazygit TUI |
| `mako` | `~/.config/mako/` | Notifications |
| `nvim` | `~/.config/nvim/` | Neovim (LazyVim) with Copilot AI autocomplete |
| `omarchy` | `~/.config/omarchy/` | Themes, hooks, extensions |
| `opencode` | `~/.config/opencode/` | OpenCode AI agent config (ai/ merge + MCP generation post-hook) |
| `walker` | `~/.config/walker/` | App launcher |
| `waybar` | `~/.config/waybar/` | Status bar layout and styling |

### Files NOT Symlinked (reference or generated)

| File | Notes |
|------|-------|
| `.bashrc` | Reference for non-managed systems — never symlinked |
| `~/.ssh/config` | Generated by `install.sh` — not a symlink |

### AI Config (`ai/`)

Shared AI agent configuration owned by this dotfiles repo at `~/.dotfiles/ai/`. Replaces the former ECC submodule.

**What `install_ai_claude()` does:**

- Cleans stale symlinks (both `ai/` and legacy `ecc/` paths) via `clean_ai_symlinks()`
- Symlinks agents, commands, skills, rules from `ai/` into `~/.claude/` via `link_directory_contents`

**What `install_ai_opencode()` does:**

- Symlinks commands and skills from `ai/` into `~/.config/opencode/`
- Runs `ai/scripts/generate-opencode-config.sh` to convert agent markdown to OpenCode JSON

**Shared MCP:** `generate_mcp_configs()` reads `~/.dotfiles/ai/mcp-servers.json.tpl` (Claude Desktop format with `op://` refs), resolves secrets via 1Password, and writes to both `~/.claude.json` (mcpServers) and `~/.config/opencode/opencode.json` (mcp)

**Idempotency:** `clean_ai_symlinks()` runs before every install, removing any symlinks in the target directory that point into `~/.dotfiles/ai/` (or legacy `ecc/`).

**1Password:** `op_inject_multi()` resolves `op://` secret references across multiple 1Password accounts by building a vault-to-account map and using `op read` per-secret (standard `op inject` only supports one account per call).

See [docs/ai.md](docs/ai.md) for how to add agents, commands, skills, and rules.

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

## Dotfiles Methodologies

### Symlink Strategy: Merge vs Replace

Use `link_file` (symlinks the entire directory) when the directory is exclusively owned by one source. Use `link_directory_contents` (symlinks each item inside) when personal files need to coexist alongside sourced files. Example: `~/.claude/commands/` uses `link_directory_contents` so personal commands coexist with `ai/` commands.

### Dynamic Config Merging

When two sources contribute to a single config file (e.g., generated AI agents + personal config in `opencode.json`), merge at install time using `jq -s '.[0] * .[1]'` rather than maintaining a combined copy. The base config comes first, personal overrides second (wins on conflicts). This eliminates duplication and keeps each source independently maintainable.

### Shared MCP Configuration

MCP servers are defined once in `~/.dotfiles/ai/mcp-servers.json.tpl` (Claude Desktop format with `op://` secret references) and generated into tool-specific formats at install time:
- **Claude Code**: merged into `~/.claude.json` as `mcpServers`
- **OpenCode**: converted to OpenCode format and merged into `~/.config/opencode/opencode.json` as `mcp`

Secrets are resolved via `op_inject_multi()` during generation. Add/remove servers by editing `ai/mcp-servers.json.tpl` and running `dot update` or `./install.sh`.

### Gitignore for Generated Symlinks in Stowed Dirs

When creating symlinks inside a stowed directory (e.g., `~/.config/opencode/commands/`), those symlinks resolve through the stow symlink into the dotfiles git tree and show as unstaged changes. Add them to the package's `.gitignore` to prevent this.

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
4. Run `bash tools/check-descriptions.sh` — description must be single-line, ≤60 chars
5. Update `docs/functions.md` with examples
6. `dot` CLI auto-parses documented functions
7. Update README.md for major utilities

### Adding a New Tool to packages.yaml

1. Add entry to `packages.yaml` with description and per-OS package names
2. Use `null` for OS package managers that don't have the tool
3. If needed, create `tools/install-<tool>.sh` as a fallback script
4. Test: `dot install <tool>`
5. Update README.md tool list

### Adding a New App Config to omadot

> **STOP — read this before touching `~/.config/` directly.**
> All configs are managed via omadot. Create files in the dotfiles repo first, then stow.

**For a brand-new tool config (most common case):**

1. **Create files in the dotfiles repo:**
   ```bash
   mkdir -p ~/.dotfiles/<pkg>/.config/<pkg>/
   # Write config files there, e.g.:
   # ~/.dotfiles/<pkg>/.config/<pkg>/config.toml
   ```
2. **Stow it** — creates the `~/.config/<pkg>` symlink:
   ```bash
   omadot put <pkg>
   ```
3. **Add a label** to `get_app_label()` in `install.sh` for the picker display
4. **Update the stow packages list** in `AGENTS.md` (both the inline list and the "Currently managed packages" table)
5. **Commit:**
   ```bash
   git add ~/.dotfiles/<pkg>/ install.sh AGENTS.md
   git commit
   ```

**To import an existing `~/.config/<pkg>/` into the dotfiles repo** (only if it already exists and isn't stowed):

1. `omadot get <pkg>` — captures from `~/.config/` into `~/.dotfiles/<pkg>/`
2. Follow steps 3–5 above

**Do NOT:**
- Write files directly to `~/.config/<pkg>/` — they won't be tracked by git
- Use `omadot get` for a brand-new config that doesn't exist in `~/.config/` yet
- Use `omadot put --all`

### Modifying install.sh

1. **No profiles or flags** — the installer is always interactive. Zsh config runs on macOS (`$OSTYPE == darwin*`), Homebrew auto-installed on macOS
2. **Core config**: `run_core_config()` always runs — shell, git submodules, ssh, git config, dot CLI
3. **App configs**: `list_app_configs()` auto-discovers stow packages + tmux + claude; `install_app_config()` handles each; `get_app_label()` provides descriptions for the picker
4. **Dev tools**: Uses `tools/lib.sh` and `packages.yaml` — gum choose for interactive selection
5. **Prerequisites**: `ensure_homebrew()`, `ensure_stow()`, `ensure_omadot()`, `ensure_jq()` auto-install if missing
6. **Idempotency**: All modules must be safe to re-run. Use `ln -snf` for symlinks, check before stowing, skip if already done. AI config uses `clean_ai_symlinks()` to remove stale links before re-linking
7. **1Password**: `op_inject_multi()` handles multi-account secret resolution (replaces `op inject` which only supports one account)
8. **Sourceable**: `main()` is guarded with `BASH_SOURCE` check so `dot.sh` can source `install.sh` for its functions
7. OS-specific paths must use `$OSTYPE` detection
8. Never replace `~/.bashrc` — only inject source line
9. SSH config is generated (not symlinked) with OS-appropriate `IdentityAgent`
10. Test with `bash -n install.sh` and `./install.sh --help`

### Modifying dot.sh

1. Sources `tools/lib.sh` for package management
2. `dot install` sources `install.sh` and calls `run_pickers()` — shows both app configs and dev tools in one interactive flow
3. `dot update` handles OS-appropriate package updates (pacman/yay, apt, brew), pulls dotfiles, updates all submodules, and re-runs `install_ai_claude` + `install_ai_opencode` if the `ai/` directory exists
4. Keep brew commands as-is (macOS only)

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
- [ ] `bash tools/check-descriptions.sh` - validate function/alias descriptions
- [ ] `source .functions && <function-name>` - test functions work
- [ ] Aliases work in new shell session
- [ ] Documentation updated (`README.md`, `docs/functions.md`, `docs/aliases.md`)
- [ ] No hardcoded personal info (use `.gitconfig.local`, `.localrc`)
- [ ] No hardcoded OS-specific paths (use `$OSTYPE` detection)
- [ ] Works on target system (macOS/Linux/Omarchy)
- [ ] `install.sh` modules work correctly
- [ ] New stow packages follow `<dir>/.config/<dir>/` structure for auto-discovery

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

## CRITICAL: How App Configs Are Managed

**ALL `~/.config/<tool>/` configs are managed via omadot (GNU Stow). Never create or edit files directly in `~/.config/`.**

When a user asks you to add, create, or update a config for any tool:

1. **Create the file in the dotfiles repo** at `~/.dotfiles/<tool>/.config/<tool>/<file>`
2. **Stow it** with `omadot put <tool>` to create the symlink `~/.config/<tool>` → `~/.dotfiles/<tool>/.config/<tool>/`
3. **Add a label** to `get_app_label()` in `install.sh` if it's a new package
4. **Update the stow packages list** in this file (`AGENTS.md`)
5. **Commit** the new/updated files under `~/.dotfiles/<tool>/`

The structure is always:
```
~/.dotfiles/<tool>/.config/<tool>/   ← files live here (tracked by git)
~/.config/<tool>                     ← symlink created by omadot put
```

**Do NOT:**
- Write files directly to `~/.config/<tool>/` — they won't be tracked
- Use `omadot get` for new configs — that captures from `~/.config/` into dotfiles; only use it if the config already exists there and you want to import it
- Use `omadot put --all` — it will try to stow non-package directories

**Currently managed packages:**
| Package | Config path in dotfiles |
|---------|------------------------|
| `btop` | `btop/.config/btop/` |
| `fastfetch` | `fastfetch/.config/fastfetch/` |
| `ghostty` | `ghostty/.config/ghostty/` |
| `hypr` | `hypr/.config/hypr/` |
| `k9s` | `k9s/.config/k9s/` |
| `kitty` | `kitty/.config/kitty/` |
| `lazygit` | `lazygit/.config/lazygit/` |
| `mako` | `mako/.config/mako/` |
| `nvim` | `nvim/.config/nvim/` |
| `omarchy` | `omarchy/.config/omarchy/` |
| `opencode` | `opencode/.config/opencode/` |
| `walker` | `walker/.config/walker/` |
| `waybar` | `waybar/.config/waybar/` |
| `worktrunk` | `worktrunk/.config/worktrunk/` |

---

For details: [README.md](README.md) | [docs/functions.md](docs/functions.md) | [docs/aliases.md](docs/aliases.md)
