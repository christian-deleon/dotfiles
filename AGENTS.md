# Agent Guidelines for Dotfiles Repository

This document provides guidelines for AI coding agents working in this personal dotfiles repository. The repository manages shell configurations, development tool setups, and system bootstrapping scripts for both macOS and Linux environments.

## Repository Overview

This is a personal dotfiles repository containing:

- Shell configurations (bash, zsh with Oh My Zsh + Powerlevel10k)
- Development tool configurations (git, vim, tmux, VS Code, Cursor)
- Package management via Homebrew (macOS) and Ansible (Linux)
- Custom aliases, functions, and shell utilities
- System setup and installation scripts

**Primary languages:** Shell (Bash), YAML (Ansible), Configuration files

## Build/Test/Run Commands

### Installation & Setup

```bash
# Initial setup (creates symlinks, configures git, installs dot CLI)
./install.sh

# Open dotfiles in preferred editor
dot edit

# Update system packages and dotfiles
dot update
```

### Tool Installation

```bash
# List available tools to install
dot install

# Install specific tool via Ansible
dot install <tool-name>
# Available: docker, kubectl, node, podman, python, starship, vim
```

### Homebrew Management (macOS)

```bash
# Install Homebrew
dot brew-install

# Install packages from profile
dot brew-bundle <profile>  # profiles: home, work

# Save current packages to profile
dot brew-save <profile>
```

### Testing Shell Scripts

```bash
# Validate shell script syntax
bash -n <script.sh>

# Run script in debug mode
bash -x <script.sh>

# Test function from .functions file
source .functions && <function-name>
```

### Ansible Validation

```bash
# Check Ansible playbook syntax
ansible-playbook --syntax-check ansible/<playbook>.yaml

# Dry-run Ansible playbook
ansible-playbook -i localhost, --check ansible/<playbook>.yaml
```

## Code Style Guidelines

### Shell Script Standards

**File Headers:**

```bash
#!/bin/bash
# or
#!/bin/bash -e  # for scripts that should exit on error

set -e  # Exit on error (if not in shebang)
```

**Variables:**

- Use UPPERCASE for environment variables and constants: `DOTFILES_DIR`, `ANSIBLE_DIR`
- Use lowercase for local variables: `local file`, `local root`
- Always quote variables: `"$variable"` not `$variable`
- Use `local` keyword for function variables

**Functions:**

```bash
# Document functions with comments above
# Description of what the function does
function my_function() {
    local arg=$1
    # Function body
}
```

**Conditionals:**

```bash
# Use [[ ]] for test conditions (bash-specific, more robust)
if [[ -f "$file" ]]; then
    # code
fi

# Pattern matching
if [[ "$var" == "value" ]]; then
if [[ "$var" =~ ^pattern ]]; then
```

**Command Checks:**

```bash
# Check if command exists
if [[ ! -x "$(command -v ansible)" ]]; then
    echo "Command not found"
fi
```

### Naming Conventions

**Files:**

- Dotfiles: `.filename` (e.g., `.bashrc`, `.aliases`)
- Scripts: `lowercase-with-hyphens.sh` (e.g., `install.sh`)
- Ansible playbooks: `action-tool.yaml` (e.g., `install-docker.yaml`, `clone-kubectl.yaml`)
- Brewfiles: `Brewfile-profile` (e.g., `Brewfile-home`, `Brewfile-work`)

**Functions:**

- Use descriptive names: `update_system()`, `install_tool()`
- Prefix Kubernetes functions: `kpa()`, `kcs()`, `ktns()`
- Prefix Git functions: `gc()`, `gaw()`, `grw()`

**Aliases:**

- Short and memorable: `k` for kubectl, `tf` for terraform, `dc` for docker compose
- Consistent prefixes for related tools (e.g., `kp`, `kpa`, `kpw` for pod operations)

### Configuration File Style

**YAML (Ansible):**

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

**Indentation:**

- YAML: 2 spaces
- Shell scripts: 4 spaces
- Maintain consistency within each file type

### Error Handling

**Shell Scripts:**

```bash
# Exit on error for critical scripts
set -e

# Check for required arguments
if [ -z "$1" ]; then
    echo "Error: Missing required argument"
    return 1
fi

# Verify file/directory exists before operations
if [ ! -f "$file" ]; then
    echo "File not found: $file"
    return 1
fi
```

## Documentation Requirements

### When Making Changes

Per `.cursor/rules/documentation.mdc`:

1. **Always update README.md** when making changes to:

   - Configurations
   - Tool installations
   - Project structure
   - New features or functionality

2. **Keep documentation current:**

   - Update Quick Start if installation steps change
   - Document system-specific differences (macOS vs Linux)
   - Update project structure diagram when adding/removing files
   - Explain new tools and their purpose

3. **Documentation standards:**
   - Use clear headings and structure
   - Include practical examples where helpful
   - Keep language simple and direct
   - Ensure README tells the complete story

### File-Level Comments

**Shell functions:**

```bash
# Description of function purpose
# Can span multiple lines if needed
function my_function() {
    # Implementation
}
```

**Ansible playbooks:**

```yaml
- name: Clear description of what this task does
  # Any special notes or warnings
  module_name:
    option: value
```

## Project-Specific Notes

### System Detection

- Scripts auto-detect macOS vs Linux using `$OSTYPE`
- macOS uses Homebrew for packages
- Linux uses Ansible for package management

### Symlink Management

- `install.sh` backs up existing files to `~/dotfiles_backup`
- All dotfiles are symlinked from repo to `$HOME`
- Directories (`.vscode`, `.config`, etc.) have individual file symlinks

### Critical Files

- `.gitconfig.local`: Personal git config (not tracked, created by install.sh)
- `.editor-config`: Editor preference (created by install.sh)
- Profile files: System-specific (`.zprofile` for macOS, `.profile`/`.bash_profile` for Linux)

### Shell Loading Order

1. Profile files (`.zprofile`, `.profile`, or `.bash_profile`)
2. RC files (`.zshrc` or `.bashrc`)
3. `.commonrc` (sourced by both bash and zsh)
4. `.aliases` and `.functions` (sourced by `.commonrc`)

### Tool-Specific Conventions

- Kubernetes configs in `~/.kube/`
- Use `kcs <config>` to switch kubeconfig
- Use `kca` to load all kubeconfigs
- SSH config optionally symlinked from `.ssh/config`

## Common Operations

### Adding New Aliases

1. Add to `.aliases` file
2. Group with related aliases (e.g., Kubernetes, Git, Docker)
3. Use consistent prefixing for discoverability
4. Update README.md if adding significant functionality

### Adding New Functions

1. Add to `.functions` file with comment above
2. Group by category (General, Kubernetes, Git, etc.)
3. The `dot` CLI will auto-parse and display documented functions
4. Update README.md for major new utilities

### Adding New Tool Installation

1. Create `ansible/install-<tool>.yaml` playbook
2. Optionally create `ansible/clone-<tool>.yaml` for repos
3. Test with `dot install <tool>`
4. Update README.md tool list

### Modifying Installation Script

1. Test on clean system if possible
2. Maintain backward compatibility
3. Always backup before overwriting files
4. Update README.md installation instructions

## Testing Checklist

Before committing changes:

- [ ] Shell scripts pass syntax check: `bash -n <script>`
- [ ] Ansible playbooks pass syntax check: `ansible-playbook --syntax-check <playbook>`
- [ ] Functions work when sourced: `source .functions && <function>`
- [ ] Aliases work in new shell session
- [ ] README.md updated if structure/functionality changed
- [ ] No hardcoded personal information (use `.gitconfig.local` or `.editor-config`)
- [ ] Changes work on target system (macOS/Linux as appropriate)
- [ ] Symlinks resolve correctly after `install.sh`

## Important Reminders

- **Personal Repository:** This is primarily for personal use; changes reflect personal preferences
- **Backup First:** `install.sh` automatically backs up existing files
- **Test Before Push:** Test changes in safe environment before committing
- **Document Everything:** Keep README.md comprehensive and up-to-date
- **System Specific:** Be aware of macOS vs Linux differences
- **Privacy:** Never commit secrets, tokens, or personal credentials

---

For questions or issues, refer to the main [README.md](README.md) or repository documentation.
