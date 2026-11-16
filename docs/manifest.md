# manifest.yaml

Single source of truth for every installable item the dotfiles repo knows about. Each top-level key is an item name (e.g. `docker`, `alacritty`, `grok`). The installer reads this file to decide:

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
    dnf:     string|null          # dnf package name (Amazon Linux 2023)
    release: object|null          # prebuilt GitHub-style release binary (see below)
    script:  string|null          # filename in scripts/tools/, for custom installers
    command: string|null          # binary name for `command -v` check + CLI alias (default: <item-name>)
    check:   string|null          # "<root>:<relpath>" presence check for items with no command on PATH
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
| `config` | no | yes | `btop` |
| `bundle` | yes | yes | `alacritty`, `neovim`, `tmux` |

Picking a bundle item installs the binary **and** the config in one step.

## How an install runs

`install_items` (`scripts/lib/engine.sh`) handles every `dot install`, profile install, and `dot update` reconcile, and acts only on what is missing:

1. **Presence.** An item counts as installed when `install.command` (default: the item name) is on `PATH`, or the `install.check` path exists. Installed items are skipped, so release binaries are not upgraded in place: delete the binary and run `dot install <item>` to fetch the latest.
2. **Install, by method:**
   - an item with a package for this host's manager (`arch`, `apt`, `brew`, `dnf`) joins one batched package-manager call, retried one package at a time if the batch fails;
   - otherwise `install.release` downloads the binary, falling back to `install.script` if the download fails;
   - otherwise `install.script` runs;
   - otherwise the item fails with "No install method".
3. **Configs**, in item order: a stow package is linked only when its `~/.config` link is missing or wrong; handlers run.
4. **`post_install` hooks**, deduplicated across the items.

Handlers and hooks run at most once per process, however many items name them. One failed item does not stop the rest; the run returns non-zero at the end.

### `install.check`

`<root>:<relpath>`, for items whose presence is a file rather than a command on `PATH`:

| Root | Directory |
|---|---|
| `xdg_config` | `$XDG_CONFIG_HOME` (default `~/.config`) |
| `xdg_data` | `$XDG_DATA_HOME` (default `~/.local/share`) |
| `xdg_state` | `$XDG_STATE_HOME` (default `~/.local/state`) |
| `xdg_cache` | `$XDG_CACHE_HOME` (default `~/.cache`) |
| `home` | `$HOME` |
| `apps` | `/Applications` (macOS app bundles) |

Examples: `blesh` uses `xdg_data:blesh/ble.sh`; `alacritty` uses `apps:Alacritty.app/Contents/MacOS/alacritty` so the macOS cask counts as installed.

### `install.release`

Installs a prebuilt binary without sudo into `${DOTFILES_BIN_DIR:-~/.local/bin}` (mode 755). Implemented in `scripts/lib/release.sh`.

```yaml
fzf:
  description: Fuzzy finder
  install:
    arch: fzf
    brew: fzf
    release:
      repo: junegunn/fzf
      asset: fzf-{version}-{os}_{arch}.tar.gz
      sums: fzf_{version}_checksums.txt
      arch: {x86_64: amd64, aarch64: arm64}
```

| Field | Meaning |
|---|---|
| `repo` | GitHub `owner/name`. The latest tag comes from the `/releases/latest` redirect (no rate-limited API); the file from `/releases/download/{tag}/<asset>`. |
| `asset` | File name in the release. |
| `latest` | URL used instead of `repo` to find the tag: the last path segment of its redirect, or its body when it does not redirect. For non-GitHub hosts. |
| `url` | Download URL used instead of `repo` + `asset`. |
| `bin` | Binary name, or a list of names (default: `install.command`, else the item name). |
| `sums` | Checksum file, as a name next to the download or a full URL, holding `<sha256>  <file>` lines or one bare hash. When set, a mismatch fails the install. |
| `os` | Supported OS (`linux`, `darwin`) → upstream name. Default `{linux: linux}`. |
| `arch` | Supported arch (`x86_64`, `aarch64`) → upstream name. Default: the same names. |

Templates take `{version}` (the tag without a leading `v`), `{tag}`, `{os}` and `{arch}`; `sums` also takes `{asset}` (the downloaded file name). A host whose OS or arch is not in the maps fails with "no release for …". A `.tar.gz`, `.tgz`, `.tar.xz` or `.zip` download is searched for each `bin` at its top, one directory down, or in a `bin/` dir; any other download is the binary itself.

Prefer `install.release` for a tool that ships release binaries. Write an `install.script` only when the upstream installer does something a download cannot (e.g. `claude`, `mise`, `blesh`, `neovim`).

On Linux, `yq` itself comes from its release through `ensure_yq` (`scripts/lib/pkg.sh`), before `manifest.yaml` can be read, so its spec lives there instead of in the manifest.

## Config types

Only two:

- **`stow`** — auto-stows from `<package>/.config/<package>/` (directory) or `<package>/.config/<package>.<ext>` (single file). Optional `package:` override lets the stow directory differ from the item name. Used for `btop`, `alacritty`, `tmux`, etc. Not used for `hypr` or `omarchy`.

- **`handler`** — calls a named bash function. Used for items that need imperative setup beyond stow: `grok` and `claude` (AI harness installers), `cargo` (`~/.cargo/config.toml` outside XDG), `cargo-sweep` (systemd user units), `windows-terminal` (Windows-side settings.json), `hypr` / `omarchy` (overlays into Omarchy-owned dirs).

Note: `opencode` and `tmux` are **`type: stow`** (with `post_install` hooks for OpenCode AI linking / MCP). They are not handlers.

Handlers live in `scripts/handlers/*.sh`, organized by domain:

| File | Functions |
|---|---|
| `scripts/handlers/ai.sh` | `install_ai_grok`, `install_ai_opencode`, `install_ai_claude`, `generate_mcp_configs`, `write_{grok,opencode,claude}_mcp` |
| `scripts/handlers/cargo.sh` | `install_cargo_config`, `install_cargo_sweep_timer` (links `cargo-sweep/systemd/*` into `~/.config/systemd/user` and enables the timer) |
| `scripts/handlers/windows.sh` | `install_windows_terminal_config` |
| `scripts/handlers/alacritty.sh` | `alacritty_setup` (theme shim + macOS Nerd Font) |
| `scripts/handlers/neovim.sh` | `install_neovim_extras` |
| `scripts/handlers/desktop.sh` | `install_hypr_config`, `install_omarchy_config` |
| `scripts/handlers/gitea.sh` | `install_tea_login` (adds the `tea` login from 1Password when it is missing) |
| `scripts/handlers/superwhisper.sh` | `install_superwhisper_config` (applies `superwhisper/config.json` through the `superwhisper` CLI) |

## CLI aliases

`dot install <name>` accepts both canonical item names and the shorthand declared in `install.command` or `config.package`. Examples:

| You type | Resolves to |
|---|---|
| `dot install op` | `1password-cli` (via `install.command: op`) |
| `dot install rg` | `ripgrep` (via `install.command: rg`) |
| `dot install nvim` | `neovim` (via `config.package: nvim`) |

Resolution is implemented by `manifest_resolve_alias` in `scripts/lib/data.sh` (the install plan applies the same rule). No separate alias table to maintain.

## Predicates (`requires:`)

Each predicate is a function `host_has_<name>` in `scripts/predicates.sh`. Available today:

| Predicate | True when |
|---|---|
| `linux`    | `$OSTYPE != darwin*` |
| `darwin`   | `$OSTYPE == darwin*` |
| `wsl`      | `/proc/version` contains "microsoft" |
| `amazonlinux` | `/etc/os-release` has `ID=amzn` |
| `omarchy`  | `~/.local/share/omarchy/` exists |
| `hyprland` | `Hyprland` command on PATH |
| `fprintd`  | `pam_fprintd.so` present in `/etc/pam.d/` |

`requires:` is a list ANDed together. An empty list (or omitted field) means the item is eligible on every host.

Adding a new predicate: append a `host_has_<name>` function to `scripts/predicates.sh`; manifest items and profiles can then reference it immediately.

## How to add a new item

1. **Add an entry to `manifest.yaml`** following the schema. Group similar items together (alphabetical is the existing convention).

2. **If `type: stow`**: create the stow package at `<item-name>/.config/<item-name>/` (directory) or `<item-name>/.config/<item-name>.<ext>` (single file). The installer auto-detects which form is in use.

3. **If `type: handler`**: add the handler function to the appropriate file in `scripts/handlers/`. Reference it by name in `manifest.yaml`. Sourcing is automatic — `scripts/lib.sh` loads every `scripts/handlers/*.sh`.

4. **If no package covers a host**: add an `install.release` entry when upstream publishes release binaries. Only for a custom installer, drop a script at `scripts/tools/install-<item-name>.sh` and reference it via `install.script`.

5. **If the item is host-restricted**: add a `requires:` list with the appropriate predicates. Define a new predicate in `scripts/predicates.sh` if none of the existing ones fit.

6. **Verify**: `bash -n install.sh`, `yq '.' manifest.yaml`, and `./install.sh --help` should all succeed. `dot install <name>` should install your new item.

## How to add a new predicate

1. Add `host_has_<name>() { ... ; return 0 (or 1); }` to `scripts/predicates.sh`.
2. Use it via `requires: [<name>]` in any manifest item or profile.
3. No further changes required — the dispatcher (`host_has`) discovers predicates by name lookup.
