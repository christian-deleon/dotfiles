# Shell Style

Conventions for shell scripts in this repo. Load when you're writing or editing `.sh` / `functions.d/*.sh` / `.aliases` / `.commonrc`.

## Output

Use `printf '%b\n'` instead of `echo -e` for escape sequence interpretation (portability).

## File structure

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

## Variables

- UPPERCASE for environment variables/constants: `DOTFILES_DIR`, `KUBECONFIG`
- lowercase for local variables: `local file`, `local namespace`
- Always quote: `"$variable"` not `$variable`
- Use `local` keyword in functions

## Conditionals

- Use `[[ ]]` not `[ ]`: `if [[ -f "$file" ]]; then`
- Pattern matching: `if [[ "$var" =~ ^pattern ]]; then`
- Command checks: `if command -v cmd &>/dev/null; then`

## OS detection

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

## Error handling

```bash
# Exit on error for critical scripts
set -e

# Check required arguments
if [[ -z "$1" ]]; then
    echo "Error: Missing required argument"
    return 1
fi
```

## Naming

**Files:**
- Dotfiles: `.filename` (`.commonrc`, `.aliases`, `.functions`)
- Function fragments: `functions.d/<topic>.sh` (`kubernetes.sh`, `git.sh`, …) — one category per file, sourced by `.functions`
- Scripts: `lowercase-with-hyphens.sh` (`install.sh`)
- Install scripts: `scripts/tools/install-<tool>.sh` (referenced as `install-<tool>.sh` in manifest)
- Brewfiles: `Brewfile-profile` (`Brewfile-home`)

**Functions:**
- Descriptive names: `update_dotfiles()`, `install_tool()`
- Kubernetes prefix: `k*` (`kcs`, `kn`, `kl`, `ke`, `kdp`)
- Git prefix: `g*` (`gc`, `gcb`)
- Many support fzf when called without arguments

**Aliases:**
- Short: `k` (kubectl), `tf` (terraform), `dc` (docker compose)
- Consistent prefixes: `kp*` (pods), `kd*` (deployments), `f*` (flux)

## YAML

Full schemas live in [manifest.md](manifest.md) and [profiles.md](profiles.md). Do not re-document them.

## Indentation

- YAML: 2 spaces
- Shell: 4 spaces

## Function comments

```bash
# Description of function purpose (can span multiple lines)
function my_function() {
    local arg="$1"
    # Implementation
}
```
