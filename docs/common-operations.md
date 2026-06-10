# Common Operations

Step-by-step walkthroughs for the most common modifications to this repo. Load this when you're about to add or change something.

## Adding new aliases

1. Add to `.aliases` file, group with related (Kubernetes, Git, Docker)
2. Use consistent prefixing (e.g., `k*` for kubectl, `f*` for flux)
3. Check for conflicts with functions in `.functions` (e.g., don't alias `sk` if `sk()` function exists)
4. Update `docs/aliases.md`
5. Update `README.md` if significant

## Adding new functions

Functions live in topic fragments under `functions.d/`. The `.functions` file is just a loader that sources every `*.sh` in that directory.

1. Pick the right fragment (`functions.d/kubernetes.sh`, `git.sh`, `aws.sh`, etc.) and add the function with a one-line `#` description above it. If the topic doesn't fit any existing fragment, create a new `functions.d/<topic>.sh` starting with `# Category: <Name>` — no other wiring is needed.
2. Consider fzf integration for interactive selection.
3. Run `bash scripts/check-descriptions.sh` — description must be single-line, ≤60 chars.
4. Update `docs/functions.md` with examples.
5. `dot` CLI auto-parses every fragment in `functions.d/`.
6. Update `README.md` for major utilities.

## Adding a tab completion

Completions live in topic fragments under `completions.d/` (mirroring `functions.d/`). A loop in `.commonrc` sources every `*.sh` for both bash and zsh — no symlink or manifest entry needed. They are written **once** in bash style and shared with zsh via `bashcompinit`.

1. Pick the right fragment (`completions.d/kubernetes.sh`, `aws.sh`, etc.) or create a new `completions.d/<topic>.sh` starting with `# Category: <Name>`.
2. Add a `_comp_<name>()` function and register it with `complete -F _comp_<name> <cmd> [<cmd>...]`. Tag the function with a `# internal:` comment (≤60 chars) so `check-descriptions.sh` skips it. Reuse the shared helpers in `completions.d/00-helpers.sh` (`_comp_reply`, `_comp_kctx`, `_comp_kns`, `_comp_aws_profiles`, …).
3. **Stay in the portable subset** (see the header in `00-helpers.sh`): only `COMP_WORDS` / `COMP_CWORD` / `compgen -W` / `complete -F`. No `compopt`, no `complete -o default`, no `_init_completion` — they break under zsh's bashcompinit.
4. Bound any remote source (`--request-timeout=2s`) and redirect `2>/dev/null` so a dead cluster degrades to an empty (silent) completion.
5. Aliases (not functions) only complete under bash; zsh covers them via alias expansion + the tool's native completion. Don't `setopt complete_aliases`.
6. Verify: `bash -n completions.d/<file>.sh`, `bash scripts/check-descriptions.sh`, then test in a fresh shell (or simulate by setting `COMP_WORDS`/`COMP_CWORD` and calling the `_comp_*` function).
7. Update the Tab completion table in `docs/functions.md`.

## Adding a new manifest item

Full walkthrough in [manifest.md](manifest.md). Short version:

1. Add an entry to `manifest.yaml` with `description`, optional `install:` block, optional `config:` block, optional `requires:` predicates.
2. For `config.type: stow`: create the stow package at `<item>/.config/<item>/`. For `config.type: handler`: add the function to the appropriate file in `scripts/handlers/`.
3. If a binary install script is needed, drop it at `scripts/tools/install-<item>.sh` and reference via `install.script`.
4. Test: `dot install <item>`.
5. Update `README.md` tool list if appropriate.

## Adding a new app config to omadot

> **STOP — read this before touching `~/.config/` directly.**
> All configs are managed via omadot. Create files in the dotfiles repo first, then stow.

**For a brand-new tool config (most common case):**

1. **Create files in the dotfiles repo:**
   ```bash
   mkdir -p ~/.dotfiles/<pkg>/.config/<pkg>/
   # Write config files there, e.g.:
   # ~/.dotfiles/<pkg>/.config/<pkg>/config.toml
   ```
2. **Add a manifest entry** with `config.type: stow` (and `description:` plus any `requires:` predicates). See [manifest.md](manifest.md).
3. **Stow it** — creates the `~/.config/<pkg>` symlink:
   ```bash
   omadot put <pkg>
   ```
4. **Add to profiles** that should include the new config (`profiles/<name>.yaml` → `items:` list).
5. **Commit:**
   ```bash
   git add ~/.dotfiles/<pkg>/ manifest.yaml profiles/
   git commit
   ```

**To import an existing `~/.config/<pkg>/` into the dotfiles repo** (only if it already exists and isn't stowed):

1. `omadot get <pkg>` — captures from `~/.config/` into `~/.dotfiles/<pkg>/`
2. Follow steps 2–5 above

**Do NOT:**
- Write files directly to `~/.config/<pkg>/` — they won't be tracked by git
- Use `omadot get` for a brand-new config that doesn't exist in `~/.config/` yet
- Use `omadot put --all`

## Modifying `install.sh`

1. **Interactive only** — no profiles or flags as CLI args. Homebrew auto-installs on macOS.
2. **Core config**: `run_core_config()` always runs — only shell config + dot CLI. Don't add anything here that depends on external services or could fail on a restricted machine.
3. **Core extras**: `get_core_extra_label()` / `install_core_extra()` define the items. Profiles list them via their `core_extras:` field; manual mode shows `run_core_extras_picker()` with host-appropriate defaults pre-selected. Adding a new extra: a new case branch in both functions + a one-line mention in `list_all_core_extras()`.
4. **Items**: declared in `manifest.yaml` (see [manifest.md](manifest.md)). `install_item` dispatches based on `config.type` (stow → `install_stow_config`, handler → `install_handler_config`). `run_post_install` runs the deduped union of `post_install:` hooks across selected items.
5. **Profile flow**: `select_profile` → `install_from_profile <name>` → writes `~/.dotfiles/.active-profile`. Manual flow: `install_manual` → no profile state written.
6. **Handlers** live in `scripts/handlers/*.sh` and are sourced automatically at install.sh startup. Handler functions are referenced from manifest by name; the dispatcher uses `declare -F` to verify existence before invocation.
7. **Prerequisites**: `ensure_homebrew()`, `ensure_yq()`, `ensure_stow()`, `ensure_omadot()`, `ensure_jq()`, `ensure_gum()` auto-install if missing.
8. **Idempotency**: All modules must be safe to re-run. Use `ln -snf` for symlinks, check before stowing, skip if already done. AI handlers use `clean_ai_symlinks()` to remove stale links before re-linking.
9. **1Password**: `op_inject_multi()` handles multi-account secret resolution. When `op` is missing or fails, `generate_mcp_configs` calls a local `drop_op_servers` jq filter to strip MCP entries containing `op://` rather than writing unresolved placeholders.
10. **Sourceable**: `main()` is guarded with `BASH_SOURCE` check so `dot.sh` can source `install.sh` for its functions.
11. OS-specific paths must use `$OSTYPE` detection (or a `host_has` predicate).
12. Never replace `~/.bashrc` — only inject source line.
13. SSH config is generated (not symlinked) with OS-appropriate `IdentityAgent`. Only generated if `ssh-config` is in the active profile's `core_extras:` (or the manual picker selection).
14. Test with `bash -n install.sh` and `./install.sh --help`.

## Modifying `dot.sh`

1. Sources `scripts/lib.sh` for manifest accessors and predicates.
2. `dot install` (no args) sources `install.sh` and calls `select_profile` then `install_from_profile`/`install_manual` — same flow as `./install.sh`.
3. `dot install <name> [<name>...]` calls `install_item` for each — manifest-driven, resolves aliases like `op` → `1password-cli`, `nvim` → `neovim`.
4. `dot profile {list,show,use}` — `manage_profile` dispatcher. State lives in `~/.dotfiles/.active-profile`; `read_active_profile` prefers the `$DOTFILES_PROFILE` env override (set in `.localrc` to force).
5. `dot update` updates OS packages, pulls dotfiles, refreshes AI symlinks, runs `update_source_tools`, then calls `reconcile_profile` (add-only: install missing items, never remove).
6. Keep brew commands as-is (macOS only).

## Modifying `.commonrc`

1. Keep it thin — only cross-platform config belongs here
2. Guard all sources: `[[ -f "$file" ]] && source "$file"`
3. Use shell detection for completions: `[[ -n "$BASH_VERSION" ]]` / `[[ -n "$ZSH_VERSION" ]]`
4. Don't duplicate what Omarchy already provides (starship, mise, zoxide, history, bash-completion)
5. Don't duplicate what `.zshrc` already provides (Homebrew, Oh My Zsh, p10k)
