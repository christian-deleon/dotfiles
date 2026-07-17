# Workflow — Editing, Validating, Installing

Authoring an AI agent file in this repo follows the same shape regardless of artifact type:

1. Edit the source under `~/.dotfiles/ai/`.
2. Validate locally (syntax check, frontmatter check).
3. Body edits to already-linked files need nothing (symlinks). New
   skills/agents/commands, or after a pull on another machine: `dot update`
   (pulls, re-links AI for Claude/OpenCode/Grok, refreshes packages).
4. Test in the target tool (restart the session if you changed a skill
   description so catalogs reload).
5. Commit (the user does this; don't commit without being asked).

This file covers the mechanics. The topic files (`skills.md`, `agents.md`, etc.) cover what to write.

## Editing — always in `~/.dotfiles/ai/`

Hard rule: source of truth is the dotfiles repo. Never edit the symlinked targets:

| Don't edit | Edit instead |
|---|---|
| `~/.claude/skills/<name>/SKILL.md` | `~/.dotfiles/ai/skills/<name>/SKILL.md` |
| `~/.claude/agents/<name>.md` | `~/.dotfiles/ai/agents/<name>.md` |
| `~/.claude/commands/<name>.md` | `~/.dotfiles/ai/commands/<name>.md` |
| `~/.claude/rules/<name>.md` | `~/.dotfiles/ai/rules/<category>/<name>.md` |
| `~/.config/opencode/skills/<name>/SKILL.md` | `~/.dotfiles/ai/skills/<name>/SKILL.md` |
| `~/.config/opencode/opencode.json` (`agent.*` / `command.*` / `instructions`) | The corresponding `ai/` source, then re-run the installer |
| `~/.grok/skills/<name>/SKILL.md` | `~/.dotfiles/ai/skills/<name>/SKILL.md` |
| `~/.grok/hooks/<script>` | `~/.dotfiles/ai/hooks/<script>` |
| `~/.claude.json` (`mcpServers`) | `~/.dotfiles/ai/mcp-servers.json.tpl` |

When the agent is in a session that's running outside `~/.dotfiles/`, `cd` there first or use absolute paths.

## Validate before installing

### Skills, agents, commands, rules (markdown)

Frontmatter must parse as YAML. Quick check:

```bash
# Replace <path> with the file you edited
python3 -c 'import sys, yaml; doc = open(sys.argv[1]).read(); fm = doc.split("---")[1] if doc.startswith("---") else ""; print(yaml.safe_load(fm))' <path>
```

Or, since most edits are skill descriptions, just eyeball the trailing `---` and check the body starts with `# Heading`.

### MCP template

```bash
jq . ~/.dotfiles/ai/mcp-servers.json.tpl
```

Should print the parsed JSON. Errors are line-numbered.

### Hooks (Grok)

If the hook is a shell script:

```bash
bash -n ~/.dotfiles/ai/hooks/<script>.sh
shellcheck ~/.dotfiles/ai/hooks/<script>.sh    # if shellcheck is installed
```

If it's inline TOML in `~/.grok/config.toml`:

```bash
# Most TOML parsers; use tomli or yq if available
python3 -c 'import tomllib; tomllib.load(open(sys.argv[1], "rb"))' ~/.dotfiles/grok/.grok/config.toml
```

## Reconcile (`dot update`)

Body-only edits to already-linked skills/rules are live via symlink — no
reconcile step. When you add a new skill/agent/command, or want this machine
to match the repo after a pull:

```bash
dot update    # pull + re-link AI (Claude/OpenCode/Grok)
```

`dot update` already calls `install_ai_claude` / `install_ai_opencode` /
`install_ai_grok` after the git pull. That is the normal path — do not invent
extra AI-only install wrappers.

MCP template changes (secrets / server list):

```bash
dot mcp-regen
```

The handlers that fire (in `~/.dotfiles/scripts/handlers/ai.sh`):

| Handler | Does |
|---|---|
| `install_ai_claude` | Symlinks `ai/{agents,commands,skills,rules}/*` → `~/.claude/*`; deep-merges `ai/claude/settings.json` fragment into `~/.claude/settings.json` |
| `install_ai_opencode` | Symlinks `ai/{commands,skills}/*` → `~/.config/opencode/*`, runs `generate-opencode-config.sh` to merge agents and rules into `opencode.json` |
| `install_ai_grok` | Symlinks `ai/{skills,agents,hooks}/*` → `~/.grok/*`, links `grok/.grok/{config,pager}.toml` |
| `generate_mcp_configs` | Resolves 1Password refs, writes `~/.claude.json` `mcpServers` and `~/.config/opencode/opencode.json` `mcp` |

## Test in the target tool

| Tool | How to verify |
|---|---|
| **Claude Code** | Start a new session in any directory. Type `/<skill-name>` (or trigger the description). For subagents, use the `/agents` modal. For hooks, edit a test file or run a Bash command that should fire the hook |
| **OpenCode** | Open OpenCode, check the slash-command picker for new commands, agent Tab cycle for new primary agents, `@<name>` to invoke subagents |
| **Grok** | Run `grok inspect` to confirm which skills/agents/hooks were discovered and from which source. For runtime test, invoke `/skill-name` or use `@agent-name` |
| **MCP servers** | In any tool, ask the agent to call a tool the new server exposes. Errors usually surface as "unknown tool" or "server failed to start" |

If a skill or agent doesn't show up: confirm the symlink:

```bash
ls -la ~/.claude/skills/<name>     # should be a symlink to ~/.dotfiles/ai/skills/<name>
readlink ~/.claude/skills/<name>
```

If the symlink is missing, re-run `dot update` (or `dot install claude` /
`opencode` / `grok` for that tool only).

## Common multi-step flows

### Add a new skill

1. `mkdir ~/.dotfiles/ai/skills/<name>`
2. Write `~/.dotfiles/ai/skills/<name>/SKILL.md` (see [skills.md](skills.md))
3. Validate frontmatter: must have `name:` and `description:`; optionally `compatibility: opencode`
4. Commit (when asked), then `dot update` so this machine re-links
5. Test in Claude Code / OpenCode / Grok (new session so the catalog picks it up)

### Add a new subagent

1. Write `~/.dotfiles/ai/agents/<name>.md` (see [agents.md](agents.md))
2. Validate frontmatter: must have `name:` and `description:`
3. Commit (when asked), then `dot update` — also regenerates OpenCode agent JSON
4. Verify in Claude Code's `/agents` modal or OpenCode's `@<name>` autocomplete

### Add a new MCP server

1. Edit `~/.dotfiles/ai/mcp-servers.json.tpl`
2. `jq . ~/.dotfiles/ai/mcp-servers.json.tpl` to validate
3. `dot mcp-regen`
4. Restart any running Claude Code / OpenCode / Grok session
5. Verify the server's tools are callable

### Add a new Grok hook

1. Write `~/.dotfiles/ai/hooks/<event>_<purpose>.sh` (event-prefixed name auto-registers in Grok)
2. `bash -n` and `shellcheck` the script
3. Commit (when asked), then `dot update`
4. `grok inspect` to confirm registration
5. Trigger the event in a Grok session to confirm execution

### Add a new Claude Code hook

Edit `~/.dotfiles/ai/claude/settings.json` and add the hook under the `hooks` key (see [hooks.md](hooks.md) for schema). On `dot update` (or `dot install claude`), `install_ai_claude` deep-merges the fragment into `~/.claude/settings.json` — the fragment wins on key conflicts, and arrays-per-event are replaced (not concatenated).

For handler scripts of any non-trivial size, drop them in `~/.dotfiles/ai/hooks/` or `~/.dotfiles/ai/scripts/` and reference them by absolute path from the fragment. Machine-specific keys you don't want to track (e.g., `theme`, `effortLevel`) should stay in `~/.claude/settings.json` directly — the merge preserves any keys the fragment doesn't touch.

## Committing changes

**Do not commit without being asked.** When the user asks:

1. Show them what's staged: `git status` and `git diff`.
2. Group related changes into one commit each (skills update + docs update = two commits, not one).
3. Use Conventional Commits — see the existing `commit` skill at `~/.dotfiles/ai/skills/commit/SKILL.md`.
4. Don't include `Co-Authored-By` lines unless they're already in the repo's convention (check `git log`).

For changes to this skill itself, scope as `feat(ai)` or `docs(ai)`:

```
feat(ai): add agent-files skill for authoring AI artifact files
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Skill doesn't trigger in Claude Code | Description too generic or too long | Tighten to specific phrases; check 1,536-char cap |
| Skill not visible in OpenCode | Missing `compatibility: opencode` or `name:` violates regex | Add `compatibility: opencode`; rename to `^[a-z0-9]+(-[a-z0-9]+)*$` |
| Agent not in `/agents` modal | Filename / `name:` mismatch | Make them match |
| MCP server missing after install | 1Password not signed in, or hash cache stuck | `op signin`; `dot mcp-regen` |
| `~/.config/opencode/opencode.json` looks empty | `generate-opencode-config.sh` failed | Run it manually with `bash -x` to see errors |
| Grok hook not firing | Filename doesn't start with the event name | Rename to `<eventname>_<purpose>.sh` (lowercase) |
| Symlink points to nothing | Source file deleted but installer didn't clean | `clean_ai_symlinks` runs on install; re-run `dot update` |

## When to flag back to the user

Stop and ask, don't guess, when:

- The user wants a hook that needs to work in all three tools (it requires three separate implementations — confirm before writing them).
- The user wants to commit changes (always ask before running `git commit`).
- An existing skill or agent is being significantly reshaped (e.g., split into multiple files) and you're unsure about naming.
- The change involves `manifest.yaml` or `profiles/*.yaml` (those are out-of-scope for this skill — flag to the user to confirm).

If the change is purely additive and matches existing conventions, proceed.
