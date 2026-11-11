# Workflow — Editing, Validating, Installing

Authoring an AI agent file in this repo follows the same shape regardless of artifact type:

1. Edit the source under `~/.dotfiles/ai/`.
2. Validate locally (syntax check, frontmatter check).
3. Body edits to already-linked files need nothing (symlinks). New skills/agents/hooks/rules, or after a pull on another machine: `dot update`.
4. Test in each harness the machine has (restart the session if you changed a skill description so catalogs reload).
5. Commit (the user does this; don't commit without being asked).

This file covers the mechanics. The topic files (`skills.md`, `agents.md`, etc.) cover what to write.

## Editing — always in `~/.dotfiles/ai/`

Hard rule: source of truth is the dotfiles repo. Never edit the live targets:

| Don't edit | Edit instead |
|---|---|
| `~/.grok/skills/<name>/SKILL.md` | `~/.dotfiles/ai/skills/<name>/SKILL.md` |
| `~/.grok/agents/<name>.md` | `~/.dotfiles/ai/agents/<name>.md` |
| `~/.grok/hooks/<script>` | `~/.dotfiles/ai/hooks/<script>` |
| `~/.grok/rules/<name>.md` | `~/.dotfiles/ai/rules/<category>/<name>.md` |
| MCP servers in any harness | `~/.dotfiles/ai/mcp-servers.json.tpl` (roster) or the profile's `mcp:` block, then `dot mcp-regen` |
| `~/.grok/config.toml` setting for every machine | `~/.dotfiles/grok/.grok/base.toml` then `dot update` |
| `~/.grok/config.toml` work Bedrock model | `~/.dotfiles/grok/.grok/overlays/<profile>.toml` then `dot update` |
| `~/.config/opencode/skills/<name>/SKILL.md` | same `ai/skills/` source (per-skill symlink) |
| `~/.config/opencode/opencode.json` (`agent.*` / `instructions`) | the `ai/` source, then `dot update` |
| `~/.config/opencode/opencode.json` `.provider` | `opencode/.config/opencode/opencode.json.tpl` (`BEDROCK_AWS_ACCOUNT_ID` for personal ARNs; `WORK_BEDROCK_API_KEY` or `/connect amazon-bedrock-gov` for work) |
| `~/.claude/skills/`, `agents/`, `rules/`, `settings.json` hooks | the `ai/` source (hooks: `ensure_claude_settings`), then `dot update` |

When the session is running outside `~/.dotfiles/`, `cd` there first or use absolute paths.

## Validate before installing

### Skills, agents, rules (markdown)

Frontmatter must parse as YAML. Quick check:

```bash
python3 -c 'import sys, yaml; doc = open(sys.argv[1]).read(); fm = doc.split("---")[1] if doc.startswith("---") else ""; print(yaml.safe_load(fm))' <path>
```

Or, since most edits are skill descriptions, eyeball the trailing `---` and check the body starts with `# Heading`.

### MCP template

```bash
jq . ~/.dotfiles/ai/mcp-servers.json.tpl
```

### Hooks

```bash
bash -n ~/.dotfiles/ai/hooks/<script>.sh
shellcheck ~/.dotfiles/ai/hooks/<script>.sh    # if installed
```

If you added inline TOML to the **seed** (rare — live `config.toml` is Grok-owned):

```bash
python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' ~/.dotfiles/grok/.grok/config.toml
```

## Reconcile (`dot update`)

Body-only edits to already-linked skills/rules/agents are live via symlink. When you add a new skill/agent/hook/rule, or want this machine to match the repo after a pull:

```bash
dot update    # pull + install_ai_<h> for each enabled harness
```

That is the normal path — do not invent extra AI-only install wrappers.

MCP roster or profile `mcp:` changes:

```bash
dot mcp-regen
```

Handlers in `~/.dotfiles/scripts/handlers/ai.sh` (each is a no-op for a harness the profile doesn't enable):

| Handler | Does |
|---|---|
| `install_ai_grok` | Links `ai/{skills,agents,hooks}` → `~/.grok/`; flattens `ai/rules/**` → `~/.grok/rules/`; seeds live `config.toml` if missing; merges `grok/.grok/base.toml` and any Grok-only profile overlay; forces `[compat.claude]` off; merges trusted folders; links `pager.toml` |
| `install_ai_opencode` | Per-skill links in `~/.config/opencode/skills/`; generates JSON agents + instructions + `.provider` from the tpl. Skips until `~/.config/opencode` is stowed |
| `install_ai_claude` | Per-skill and agent symlinks, flattened rules, notify hooks + blank attribution merged into `settings.json` |
| `generate_mcp_configs` | Picks servers from the profile `mcp:` block, resolves 1Password refs for those only; writes Grok `[mcp_servers.*]`, OpenCode `mcp.servers`, Claude `mcpServers` |

## Test

| Surface | How |
|---|---|
| **Grok skills / agents / hooks** | `grok inspect` — confirm source and path. Runtime: `/skill-name`, or spawn the subagent |
| **Grok MCP** | `grok inspect` — servers should show source `config`. Then ask the agent to call a tool |
| **OpenCode** | Slash picker / `@<name>` / Tab cycle |
| **Claude Code** | `/skills`, `/agents`, `/hooks`, `claude mcp list` |

If a skill doesn't show up, check the harness's skills dir:

```bash
readlink ~/.grok/skills/<name> ~/.config/opencode/skills/<name> ~/.claude/skills/<name>
```

Missing symlink → `dot update`. Still missing → the harness isn't in the active profile's `items:`.

## Common multi-step flows

### Add a new skill

1. `mkdir ~/.dotfiles/ai/skills/<name>`
2. Write `SKILL.md` (see [skills.md](skills.md))
3. Frontmatter must have `name:` and `description:`
4. Commit (when asked), then `dot update`
5. New session so the catalog picks it up. `/<name>` or trigger the description

### Add a new subagent

1. Write `~/.dotfiles/ai/agents/<name>.md` (see [agents.md](agents.md))
2. Frontmatter: `name:`, `description:`; omit `model` to inherit in every harness
3. `dot update` — links it for Grok and Claude, regenerates OpenCode agent JSON
4. `grok inspect` / Claude `/agents`

### Add a new MCP server

1. Edit `~/.dotfiles/ai/mcp-servers.json.tpl`
2. `jq .` to validate
3. Add the name to `mcp.enable` in each profile that should run it
4. `dot mcp-regen`
5. Restart the harnesses. `grok inspect` / `claude mcp list`

### Add a new hook

1. Write `~/.dotfiles/ai/hooks/<event>_<purpose>.sh` (see [hooks.md](hooks.md))
2. `bash -n` / `shellcheck`
3. Register it for Grok (`ai/hooks/dotfiles.json`), Claude (`ensure_claude_settings`) and OpenCode (plugin) as needed
4. `dot update`
5. `/hooks` in each harness; trigger the event

## Committing changes

**Do not commit without being asked.** When the user asks:

1. `git status` and `git diff`.
2. Group related changes (skill + docs = two commits if they're separable).
3. Conventional Commits — see the `commit` skill.

For this skill itself, scope as `feat(ai)` or `docs(ai)`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Skill doesn't trigger | Description too generic or too long | Tighten phrases; stay ~250–350 chars (OpenCode cap 1,024) |
| Skill not visible in OpenCode | `name:` violates regex or doesn't match the dir | Rename to `^[a-z0-9]+(-[a-z0-9]+)*$` |
| Skill/MCP missing in one harness only | Harness not in the active profile's `items:` | Add it to the profile, `dot update` |
| Agent missing in Grok | Filename / `name:` mismatch | Make them match |
| MCP missing after regen | 1Password not signed in, or hash cache stuck | `op signin`; `FORCE_MCP_REGEN=true` / `dot mcp-regen` |
| `opencode.json` looks empty | `generate-opencode-config.sh` failed | `bash -x` the script |
| Grok hook not firing | No entry in `ai/hooks/dotfiles.json`; or script reads snake_case only | Add the entry; read `.toolInput` / `.hookEventName` |
| Hook fires in Grok only | Not registered for Claude / OpenCode | Add to `ensure_claude_settings` / an OpenCode plugin |
| Symlink points to nothing | Source deleted | `dot update` (`clean_ai_symlinks` runs first) |

## When to flag back to the user

Stop and ask, don't guess, when:

- They want the same hook behavior in OpenCode (that's a plugin — confirm before writing).
- They want to commit (always ask before `git commit`).
- An existing skill/agent is being split or renamed and you're unsure.
- The change involves `manifest.yaml` or `profiles/*.yaml` beyond a profile's `mcp:` block (out of scope for this skill).

If the change is purely additive and matches existing conventions, proceed.
