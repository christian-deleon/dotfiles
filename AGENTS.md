# Agent Guidelines for Dotfiles Repository

Guidelines for AI coding agents working in this personal dotfiles repository. This repository manages shell configurations, development tool setups, and system bootstrapping scripts for macOS and Linux.

## Repository Overview

**Primary Languages:** Shell (Bash), YAML (Ansible), Configuration files

**Key Components:**

- Shell configs: bash, zsh with Oh My Zsh + Powerlevel10k + fzf
- Dev tool configs: git, vim, tmux, VS Code, Cursor
- Package management: Homebrew (macOS), Ansible (Linux)
- Custom aliases, functions (many with fzf integration), shell utilities
- Documentation: `docs/functions.md`, `docs/aliases.md`

## Build/Test/Run Commands

### Testing & Validation

```bash
# Test single shell script syntax
bash -n .functions

# Debug single script
bash -x install.sh

# Test single function
source .functions && kcs

# Validate single Ansible playbook
ansible-playbook --syntax-check ansible/install-docker.yaml

# Dry-run single playbook
ansible-playbook -i localhost, --check ansible/install-docker.yaml

# Test all shell files
for f in .[a-z]*; do [[ -f "$f" ]] && bash -n "$f" 2>&1 | grep -v "cannot execute" || true; done
```

### Installation & Management

```bash
./install.sh              # Initial setup (symlinks, git config, dot CLI)
dot edit                  # Open dotfiles in preferred editor
dot update                # Update system packages and dotfiles
dot install               # List available tools
dot install <tool-name>   # Install via Ansible (docker, kubectl, node, etc.)
```

### Homebrew (macOS only)

```bash
dot brew-install          # Install Homebrew
dot brew-bundle <profile> # Install from profile (home, work)
dot brew-save <profile>   # Save current packages to profile
```

## Code Style Guidelines

### Shell Script Standards

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
- Command checks: `if [[ ! -x "$(command -v cmd)" ]]; then`

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

- Dotfiles: `.filename` (`.bashrc`, `.aliases`, `.functions`)
- Scripts: `lowercase-with-hyphens.sh` (`install.sh`)
- Ansible: `action-tool.yaml` (`install-docker.yaml`)
- Brewfiles: `Brewfile-profile` (`Brewfile-home`)

**Functions:**

- Descriptive names: `update_system()`, `install_tool()`
- Kubernetes prefix: `k*` (`kcs`, `kn`, `kl`, `ke`, `kdp`)
- Git prefix: `g*` (`gc`, `gaw`, `grw`, `gcbare`)
- Many support fzf when called without arguments

**Aliases:**

- Short: `k` (kubectl), `tf` (terraform), `dc` (docker compose)
- Consistent prefixes: `kp*` (pods), `kd*` (deployments), `f*` (flux)

### YAML (Ansible)

```yaml
---
- name: Descriptive task name
  hosts: localhost
  connection: local
  tasks:
    - name: Action description
      become: yes
      package:
        name: package-name
        state: present
```

**Indentation:** 2 spaces (YAML), 4 spaces (Shell)

## Documentation Requirements

**Always update when making changes:**

1. **README.md** - configurations, tools, structure, features
2. **docs/functions.md** - new/modified functions with examples
3. **docs/aliases.md** - new/modified aliases

**Standards (per `.cursor/rules/documentation.mdc`):**

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

```yaml
- name: Clear description of what this task does
  # Special notes or warnings
  module_name:
    option: value
```

## Project-Specific Notes

### System Detection & Packages

- Auto-detect OS: `$OSTYPE` (macOS vs Linux)
- macOS: Homebrew for packages
- Linux: Ansible for packages

### Symlinks & Critical Files

- `install.sh` backs up to `~/dotfiles_backup`, symlinks to `$HOME`
- `.gitconfig.local` - personal config (not tracked, created by install.sh)
- `.editor-config` - editor preference (created by install.sh)
- Profile files: `.zprofile` (macOS), `.profile`/`.bash_profile` (Linux)

### Shell Loading Order

1. Profile files (`.zprofile`, `.profile`, `.bash_profile`)
2. RC files (`.zshrc`, `.bashrc`)
3. `.commonrc` (sourced by both)
4. `.aliases` and `.functions` (sourced by `.commonrc`)

### Tool-Specific

- Kubernetes: configs in `~/.kube/`, use `kcs` (select config), `kca` (load all)
- fzf: Many functions (`kcs`, `kn`, `kc`, `kl`, `ke`, etc.) use fzf when no args provided

## Common Operations

### Adding New Aliases

1. Add to `.aliases` file, group with related (Kubernetes, Git, Docker)
2. Use consistent prefixing (e.g., `k*` for kubectl, `f*` for flux)
3. Update `docs/aliases.md`
4. Update README.md if significant

### Adding New Functions

1. Add to `.functions` with comment above
2. Group by category (General, Kubernetes, Git, etc.)
3. Consider fzf integration for interactive selection
4. Update `docs/functions.md` with examples
5. `dot` CLI auto-parses documented functions
6. Update README.md for major utilities

### Adding Tool Installation

1. Create `ansible/install-<tool>.yaml` playbook
2. Optional: `ansible/clone-<tool>.yaml` for repos
3. Test: `dot install <tool>`
4. Update README.md tool list

### Modifying install.sh

1. Test on clean system if possible
2. Maintain backward compatibility
3. Always backup before overwrite
4. Update README.md

## Testing Checklist

Before committing:

- [ ] `bash -n <script>` - shell syntax check
- [ ] `ansible-playbook --syntax-check <playbook>` - Ansible validation
- [ ] `source .functions && <function-name>` - test functions work
- [ ] Aliases work in new shell session
- [ ] Documentation updated (`README.md`, `docs/functions.md`, `docs/aliases.md`)
- [ ] No hardcoded personal info (use `.gitconfig.local`, `.editor-config`)
- [ ] Works on target system (macOS/Linux)
- [ ] Symlinks resolve after `install.sh`

## Important Reminders

- **Personal repo** - changes reflect personal preferences
- **Backup first** - `install.sh` auto-backs up to `~/dotfiles_backup`
- **Test before push** - validate in safe environment
- **Document everything** - keep docs comprehensive and current
- **System-specific** - be aware of macOS vs Linux differences
- **Privacy** - never commit secrets, tokens, credentials
- **fzf integration** - many kubectl/git functions support interactive mode

---

For details: [README.md](README.md) | [docs/functions.md](docs/functions.md) | [docs/aliases.md](docs/aliases.md)
