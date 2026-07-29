# Tombstones

Desired-state **absences** for residue left by retired tools and configs.

When you remove something from the repo (or stop shipping it), profile reconcile is **add-only** and will not delete leftover files on other machines. Tombstones fill that gap for **path cleanup** without a versioned migration ledger.

## When to use

| Situation | Mechanism |
|-----------|-----------|
| Dropped stow package (repo dir gone) | `clean_stale_dotfile_symlinks` (dangling `~/.config/<pkg>`) |
| Script install / XDG / home residue | **Tombstone** entry in `tombstones.yaml` |
| Config rewrite / one-shot surgery | Future: small migration script (escape hatch only) |
| OS package uninstall (brew/pacman/apt) | Manual — not automated |

Prefer a tombstone over a one-shot script whenever the cleanup is “these paths must not exist.”

## Schema

File: `tombstones.yaml` (repo root).

```yaml
<item-or-id>:
  description: string        # required — why; logged when removing
  requires: [string]         # optional host predicates (same as manifest)
  xdg_config: [name]         # under $XDG_CONFIG_HOME (default ~/.config)
  xdg_data:   [name]         # under $XDG_DATA_HOME
  xdg_state:  [name]         # under $XDG_STATE_HOME
  xdg_cache:  [name]         # under $XDG_CACHE_HOME
  home:       [name]         # under $HOME (e.g. .somerc)
```

**Names** must be a single path segment (no `/`, no `..`). That keeps every removal under a known root.

## Lifecycle

1. Author retires a tool (delete package / manifest item / profile entries).
2. Add a tombstone listing every residue path the old install could have created.
3. Commit. On each machine, `dot update` (or `./install.sh`) runs `apply_tombstones`.
4. Residue is removed if present; later runs are no-ops.
5. Optionally delete the tombstone entry months later if you no longer care about ancient machines — not required.
6. When reintroducing a tool, **delete its tombstone first** — otherwise `dot update` will keep removing its install.

## When it runs

| Entry point | Order |
|-------------|--------|
| `dot update` | After git pull / stale-symlink cleanup; before source-tool rebuild and profile reconcile |
| `./install.sh` / `dot install` core config | Right after `clean_stale_dotfile_symlinks` |

Implementation: `apply_tombstones()` in `scripts/lib.sh`.

## Example — retired script-installed tool

```yaml
exampletool:
  description: Retired exampletool install and config
  xdg_config: [exampletool]
  xdg_data: [exampletool]
  xdg_state: [exampletool]
  xdg_cache: [exampletool]
  home: [.exampletoolrc]
```

## Safety

- Idempotent: missing paths are skipped.
- Scoped: only roots above; names cannot escape with `../`.
- Optional `requires:` so a Linux-only residue is not even inspected on macOS (optional — omitting `requires` is fine; missing paths no-op).
- Does **not** uninstall package-manager packages.

## Adding a tombstone (checklist)

1. Confirm the install path(s): stow link, `~/.local/share/<name>`, caches, home files.
2. Add an entry to `tombstones.yaml`.
3. `yq '.' tombstones.yaml` parses.
4. Dry-check: create a dummy dir matching a path, run:
   ```bash
   source ~/.dotfiles/scripts/lib.sh && apply_tombstones
   ```
5. Document in the commit body if non-obvious.
