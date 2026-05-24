# manifest.yaml

Single source of truth for every installable item the dotfiles repo knows about. Each top-level key is an item name (e.g. `docker`, `alacritty`, `claude`). The installer reads this file to decide:

1. What items exist (used by the picker, `dot install <name>`, and profiles)
2. How to install each item (binary install methods, config type, post-install hooks)
3. Whether each item is eligible on the current host (`requires:` predicates)

Profiles in `profiles/*.yaml` reference manifest items by name. See [docs/profiles.md](profiles.md).

## Schema

```yaml
<item-name>:
  description: string             # required — picker label, --help, docs
  install:                        # optional — present iff item has a binary install
    arch:    string|null          # pacman/yay package name
    apt:     string|null          # apt package name
    brew:    string|null          # homebrew formula (may include "--cask " prefix)
    script:  string|null          # filename in scripts/tools/, fallback when no native package
    command: string|null          # binary name for `command -v` check + CLI alias (default: <item-name>)
    update:  bool                 # default false; if true, rebuilt by `dot update`
  config:                         # optional — present iff item has a config side
    type:    stow|handler         # exactly two types
    package: string|null          # stow package override (only for type: stow); default <item-name>
    handler: string|null          # bash function name (only for type: handler)
  post_install: [string]          # bash function names to run after install (deduped across items)
  requires: [string]              # host predicates ANDed; default empty (eligible everywhere)
```

## Item kinds

The installer classifies items based on which blocks are present:

| Kind | Has `install`? | Has `config`? | Example |
|--------|---|---|------------|
| `tool` | yes | no | `docker`, `jq` |
| `config` | no | yes | `btop`, `claude` |
| `bundle` | yes | yes | `alacritty`, `neovim`, `tmux` |

Picking a bundle item installs the binary **and** the config in one step.

## Config types

Only two:

- **`stow`** — auto-stows from `<package>/.config/<package>/` (directory) or `<package>/.config/<package>.<ext>` (single file). Optional `package:` override lets the stow directory differ from the item name. Used for `btop`, `alacritty`, `omarchy`, etc.

- **`handler`** — calls a named bash function. Used for items that need imperative setup beyond stow: the four AI items (`claude`, `grok`, `opencode`), `tmux` (direct symlinks for `.tmux.conf` and `.tmux/`), `lid-check` (PAM patch), `windows-terminal` (Windows-side settings.json).

Handlers live in `scripts/handlers/*.sh`, organized by domain:

| File | Functions |
|---|---|
| `scripts/handlers/ai.sh` | `install_ai_claude`, `install_ai_grok`, `install_ai_opencode`, `generate_mcp_configs` |
| `scripts/handlers/cargo.sh` | `install_cargo_config` |
| `scripts/handlers/tmux.sh` | `install_tmux_config` |
| `scripts/handlers/linux.sh` | `install_lid_check` |
| `scripts/handlers/windows.sh` | `install_windows_terminal_config` |
| `scripts/handlers/alacritty.sh` | `alacritty_theme_shim` |
| `scripts/handlers/neovim.sh` | `install_neovim_extras` |

## CLI aliases

`dot install <name>` accepts both canonical item names and the shorthand declared in `install.command` or `config.package`. Examples:

| You type | Resolves to |
|---|---|
| `dot install op` | `1password-cli` (via `install.command: op`) |
| `dot install rg` | `ripgrep` (via `install.command: rg`) |
| `dot install nvim` | `neovim` (via `config.package: nvim`) |
| `dot install wt` | `worktrunk` (via `install.command: wt`) |

Resolution is implemented by `manifest_resolve_alias` in `scripts/lib.sh`. No separate alias table to maintain.

## Predicates (`requires:`)

Each predicate is a function `host_has_<name>` in `scripts/predicates.sh`. Available today:

| Predicate | True when |
|---|---|
| `linux`    | `$OSTYPE != darwin*` |
| `darwin`   | `$OSTYPE == darwin*` |
| `wsl`      | `/proc/version` contains "microsoft" |
| `omarchy`  | `~/.local/share/omarchy/` exists |
| `hyprland` | `Hyprland` command on PATH |
| `fprintd`  | `pam_fprintd.so` present in `/etc/pam.d/` |

`requires:` is a list ANDed together. An empty list (or omitted field) means the item is eligible on every host.

Adding a new predicate: append a `host_has_<name>` function to `scripts/predicates.sh`; manifest items and profiles can then reference it immediately.

## How to add a new item

1. **Add an entry to `manifest.yaml`** following the schema. Group similar items together (alphabetical is the existing convention).

2. **If `type: stow`**: create the stow package at `<item-name>/.config/<item-name>/` (directory) or `<item-name>/.config/<item-name>.<ext>` (single file). The installer auto-detects which form is in use.

3. **If `type: handler`**: add the handler function to the appropriate file in `scripts/handlers/`. Reference it by name in `manifest.yaml`. Sourcing is automatic — install.sh loads every `scripts/handlers/*.sh` at startup.

4. **If the item needs a tool install script**: drop it at `scripts/tools/install-<item-name>.sh` and reference it via `install.script`.

5. **If the item is host-restricted**: add a `requires:` list with the appropriate predicates. Define a new predicate in `scripts/predicates.sh` if none of the existing ones fit.

6. **Verify**: `bash -n install.sh`, `yq '.' manifest.yaml`, and `./install.sh --help` should all succeed. `dot install <name>` should install your new item.

## How to add a new predicate

1. Add `host_has_<name>() { ... ; return 0 (or 1); }` to `scripts/predicates.sh`.
2. Use it via `requires: [<name>]` in any manifest item or profile.
3. No further changes required — the dispatcher (`host_has`) discovers predicates by name lookup.
