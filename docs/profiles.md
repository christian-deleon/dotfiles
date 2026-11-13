# Profiles

A **profile** is a curated set of manifest items + core extras for a specific machine context. Profiles live in `profiles/*.yaml` and are hand-authored — `./install.sh` reads them, the picker shows the ones compatible with the current host, and picking one installs everything end-to-end.

Profiles are read-only at runtime: the installer never edits them. To change what a profile installs, edit the YAML and commit.

## Why profiles

Tools-and-configs as a flat picker works, but a fresh machine forces you to remember "what did I install last time?" Profiles answer that with a name. `./install.sh` → pick `omarchy-personal` (or whatever) → ten minutes later your machine is set up the same as the last one with that profile.

Profiles also encode environment context: a profile that requires WSL won't appear in the picker on a macOS box. The picker on each host shows only what's actually applicable plus the manual fallback.

## Schema

```yaml
name: string                # must match filename without .yaml
description: string         # one-line summary, shown in picker
requires: [string]          # host predicates ANDed; profile hidden if any fail
core_extras: [string]       # subset of installer core-extras (see below)
items: [string]             # manifest.yaml keys to install
ai:
  default: string           # default AI harness (claude | grok | opencode)
mcp:
  enable: [string]          # MCP servers from ai/mcp-servers.json.tpl
  override:                 # per-server launch-field patches
    <server>: {command, args, env, url, headers, type}
models:                     # replaces ai/models.yaml entries on this machine
  <job>:
    <harness>: {model, effort}
```

### `requires:`

A list of `host_has_<predicate>` predicates that must all pass on the current host for the profile to be selectable. If any predicate fails, the profile is filtered out of the picker entirely (not shown as disabled — just hidden). Available predicates: `linux`, `darwin`, `wsl`, `amazonlinux`, `omarchy`, `hyprland`, `fprintd` (defined in `scripts/predicates.sh`).

Examples:
- `requires: [omarchy]` — Omarchy-only
- `requires: [wsl]` — WSL-only
- `requires: [darwin]` — macOS-only
- `requires: []` (or omitted) — eligible everywhere

### `core_extras:`

Profile-authoritative list of installer core extras to run. Replaces the pre-selected picker for profile-based installs. Available names:

| Name | What it does |
|---|---|
| `git-submodules`   | Initialize `.ssh` and `.tmux/plugins/tpm` submodules |
| `git-config`       | Symlink `.gitconfig`, prompt for name/email/signing |
| `ssh-config`       | Generate `~/.ssh/config` with the OS-appropriate 1Password IdentityAgent |
| `zsh-config`       | Install Oh My Zsh + Powerlevel10k + plugins, symlink `.zshrc` |
| `ai-tool`          | Write `AI_TOOL` / `AI_TOOL_RESUME` / `AI_TOOL_PIPE` into `~/.localrc` from `ai.default` (only if `~/.localrc` has no `AI_TOOL`) |
| `omarchy-themes`   | Pick Omarchy theme submodules to install |
| `default-terminal` | Set Alacritty as Omarchy's default terminal |

Profiles include only what makes sense for their environment. Example: a `macos-personal` profile lists `zsh-config`; a `wsl-personal` profile doesn't.

### `items:`

List of manifest.yaml top-level keys. The installer iterates them in order, invoking `install_item` on each. Items whose `requires:` aren't met on the host are silently skipped (so it's safe to include host-conditional items in a multi-platform profile, even though the typical pattern is one profile per host context).

Aliases (e.g. `nvim` for `neovim`, `op` for `1password-cli`) are accepted but canonical names are preferred for clarity.

The AI harness items (`claude`, `grok`, `opencode`) also gate which harnesses get configured: only listed ones receive skills, agents, rules, MCP, and `dot agent env` links. With an active profile, `dot install <harness>`, `install_item`, and the manual picker refuse a harness the profile doesn't list. The personal profiles and `dev-server` list all three; `wsl-work` lists `grok` and `opencode`.

### `ai:`

`default` — the harness `tav` / `wta` / `wtc` and commit-message generation use. Must be one of the profile's harness items. The `ai-tool` core extra and `dot update` write it into `~/.localrc` only when `~/.localrc` has no `AI_TOOL`; `dot ai-tool` overrides. Personal profiles use `claude`; `wsl-work` uses `opencode`.

### `mcp:`

The only source of which MCP servers run. Without a profile or without this block, the roster's `"default": true` servers (context7, firecrawl) are used.

- `enable` — roster names from `ai/mcp-servers.json.tpl`, written to every enabled harness. Unknown names warn.
- `override.<server>` — patches `command`, `args`, `env`, `url`, `headers`, `type`. A `command` without `args` drops the roster's args. Applied before 1Password injection and `$HOME` expansion.

```yaml
mcp:
  enable: [context7, firecrawl, kubernetes]
  override:
    kubernetes:
      command: kubernetes-mcp-server   # Ubuntu npm wedges `npx @latest`
```

### `models:`

Same shape as `ai/models.yaml`. Each `<job>.<harness>` entry replaces that whole entry (an omitted `effort` means none); jobs and harnesses not named keep the shared values. See [ai.md](ai.md#models-per-job).

```yaml
models:
  plan:
    grok: { model: us-gov.xai.grok-4.7 }
    opencode: { model: amazon-bedrock-gov/work-grok-4.7, effort: xhigh }
```

## Authoring a new profile

1. Copy the template:
   ```bash
   cp profiles/_template.yaml profiles/<your-machine>.yaml
   ```
   The template lives in `profiles/` but is filtered out of the picker by filename convention (any file starting with `_` or `.` is ignored).

2. Edit `name:` to match the filename (without `.yaml`).

3. Set `requires:` to the predicates that must pass on the target host(s). If the profile is for one specific environment (e.g. macOS dev box), pick the tightest predicate (`darwin`). If multiple, list them all (ANDed).

4. Pick `core_extras:` — only the ones that make sense for this environment.

5. Pick `items:` — a list of manifest keys. The canonical reference is `manifest.yaml` itself; run `./install.sh --help` to see every item with its description.

6. Test: on a host that satisfies `requires:`, run `./install.sh` and confirm the profile appears in the picker. Pick it; verify the install runs end-to-end. Run `dot profile show` to confirm `.active-profile` was written.

## Active profile state

The installer (and `dot profile use`) writes the picked profile name to `~/.dotfiles/.active-profile` — a single-line, gitignored file. `.commonrc` reads it on shell startup and exports `DOTFILES_PROFILE` so scripts can branch on it; `dot` re-reads the file, so `dot profile use` takes effect without a new shell.

To force a specific profile on a machine without re-running the installer, set `DOTFILES_PROFILE=<name>` in `~/.localrc`; this takes precedence over `.active-profile`.

`install_from_profile` exports `DOTFILES_PROFILE=<name>` for the duration of the install, so `dot profile use X` and fresh installs see X. It refuses if `~/.localrc` pins a different `DOTFILES_PROFILE`.

## Drift handling (`dot update`)

When a profile is active, `dot update` reconciles missing items: it iterates the profile's `items:` list and calls `install_item` on each. Grok always upserts `grok/.grok/base.toml` into live `~/.grok/config.toml`, then upserts `grok/.grok/overlays/<profile>.toml` when that overlay exists (Grok-only settings, e.g. `wsl-work` pins org Bedrock; personal profiles have none). The overlay wins on conflict. MCP comes from the profile's `mcp:` block, not the overlay. Idempotent — already-installed items are no-ops; new items get installed. **Removed profile items are not uninstalled by reconcile** (add-only), so package-manager packages stay until you remove them yourself.

Residue from **retired** tools (paths we used to create) is handled separately by **tombstones** — `apply_tombstones` runs on every `dot update` and removes paths listed in `tombstones.yaml` if they still exist. See [tombstones.md](tombstones.md).

If no profile is active (e.g. you used Manual mode), `dot update` skips item reconciliation entirely — it still pulls dotfiles, refreshes AI, applies tombstones, and rebuilds source tools.

## Unattended install

`./install.sh --profile <name>` runs the core config and then that profile with no picker, for provisioning tools such as Ansible. Re-running it is safe: installed tools are skipped, links are re-checked, and `.active-profile` is rewritten. It exits non-zero if the profile is unknown or its `requires:` fail.

With no terminal, the `git-config` extra only links `~/.gitconfig` and leaves `~/.gitconfig.local` as it is, so the provisioner writes that file first. A profile without the `ssh-config` extra skips the `.ssh` submodule.

## Manual mode

The picker always includes "Manual selection" as the last option. Picking it shows the core-extras picker (host-appropriate defaults pre-selected) and then the full item picker. No active-profile state is written — manual mode is ephemeral.

Useful for: ad-hoc installs, recovery, experimenting before committing to a profile.

## Switching profiles

```bash
dot profile list                  # show profiles with compat/active markers
dot profile show                  # print the currently active profile
dot profile use <name>            # switch active profile + reconcile
```

`dot profile use` aborts if the requested profile's `requires:` aren't met on the host. There's no `dot profile save` — profiles are hand-authored by intent.

## Cross-references

- Manifest schema: [docs/manifest.md](manifest.md)
- Predicate definitions: `scripts/predicates.sh`
- Profile installer: `install.sh:install_from_profile`
- Profile picker: `install.sh:select_profile`
- Drift reconciliation: `dot.sh:reconcile_profile`
