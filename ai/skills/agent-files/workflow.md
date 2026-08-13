# Workflow — Editing, Validating, Installing

Authoring an AI agent file in this repo follows the same shape regardless of artifact type:

1. Edit the source under `~/.dotfiles/ai/`.
2. Validate locally (syntax check, frontmatter check).
3. Body edits to already-linked files need nothing (symlinks). New skills/agents/hooks/rules, or after a pull on another machine: `dot update`.
4. Test in Grok (restart the session if you changed a skill description so catalogs reload). OpenCode only if you care about the adapter.
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
| `~/.grok/config.toml` `[mcp_servers.*]` | `~/.dotfiles/ai/mcp-servers.json.tpl` then `dot mcp-regen` |
| `~/.config/opencode/skills/<name>/SKILL.md` | same `ai/skills/` source (that's a dir symlink) |
| `~/.config/opencode/opencode.json` (`agent.*` / `instructions` / `mcp`) | the `ai/` source, then `dot update` / `dot mcp-regen` |

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

### Hooks (Grok)

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
dot update    # pull + install_ai_grok + OpenCode adapter
```

That is the normal path — do not invent extra AI-only install wrappers.

MCP template changes (secrets / server list):

```bash
dot mcp-regen
```

Handlers in `~/.dotfiles/scripts/handlers/ai.sh`:

| Handler | Does |
|---|---|
| `install_ai_grok` | Links `ai/{skills,agents,hooks}` → `~/.grok/`; flattens `ai/rules/**` → `~/.grok/rules/`; seeds live `config.toml` if missing; forces `[compat.claude]` off; merges trusted folders; links `pager.toml` |
| `install_ai_opencode` | `~/.config/opencode/skills` → `~/.grok/skills`; hops `AGENTS.md`; generates JSON agents + instructions |
| `generate_mcp_configs` | Resolves 1Password refs; writes Grok `[mcp_servers.*]` and OpenCode `mcp` |

## Test

| Surface | How |
|---|---|
| **Grok skills / agents / hooks** | `grok inspect` — confirm source and path. Runtime: `/skill-name`, or spawn the subagent |
| **Grok MCP** | `grok inspect` — servers should show source `config`. Then ask the agent to call a tool |
| **OpenCode adapter** | Slash picker / `@<name>` / Tab cycle. Skills resolve through the dir symlink |

If a skill doesn't show up:

```bash
ls -la ~/.grok/skills/<name>     # symlink to ~/.dotfiles/ai/skills/<name>
readlink ~/.grok/skills/<name>
```

Missing symlink → `dot update` (or `dot install grok`).

## Common multi-step flows

### Add a new skill

1. `mkdir ~/.dotfiles/ai/skills/<name>`
2. Write `SKILL.md` (see [skills.md](skills.md))
3. Frontmatter must have `name:` and `description:`; keep `compatibility: opencode`
4. Commit (when asked), then `dot update`
5. New Grok session so the catalog picks it up. `/<name>` or trigger the description

### Add a new subagent

1. Write `~/.dotfiles/ai/agents/<name>.md` (see [agents.md](agents.md))
2. Frontmatter: `name:`, `description:`, `model: grok-build` (or omit)
3. `dot update` — also regenerates OpenCode agent JSON
4. `grok inspect`

### Add a new MCP server

1. Edit `~/.dotfiles/ai/mcp-servers.json.tpl`
2. `jq .` to validate
3. Always-on? Add to `enabled_mcp_servers` in `scripts/handlers/ai.sh`
4. `dot mcp-regen`
5. Restart Grok. `grok inspect`

### Add a new Grok hook

1. Write `~/.dotfiles/ai/hooks/<event>_<purpose>.sh` (see [hooks.md](hooks.md))
2. `bash -n` / `shellcheck`
3. `dot update`
4. `grok inspect` + `/hooks`
5. Trigger the event

## Committing changes

**Do not commit without being asked.** When the user asks:

1. `git status` and `git diff`.
2. Group related changes (skill + docs = two commits if they're separable).
3. Conventional Commits — see the `commit` skill.
4. Don't add `Co-Authored-By` unless `git log` already uses it.

For this skill itself, scope as `feat(ai)` or `docs(ai)`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Skill doesn't trigger | Description too generic or too long | Tighten phrases; stay ~250–350 chars (OpenCode cap 1,024) |
| Skill not visible in OpenCode | Missing `compatibility: opencode` or `name:` violates regex | Add the flag; rename to `^[a-z0-9]+(-[a-z0-9]+)*$` |
| Agent missing in Grok | Filename / `name:` mismatch | Make them match |
| MCP missing after regen | 1Password not signed in, or hash cache stuck | `op signin`; `FORCE_MCP_REGEN=true` / `dot mcp-regen` |
| `opencode.json` looks empty | `generate-opencode-config.sh` failed | `bash -x` the script |
| Grok hook not firing | Filename doesn't start with the event; or script reads snake_case only | Rename; read `.toolInput` / `.hookEventName` |
| Symlink points to nothing | Source deleted | `dot update` (`clean_ai_symlinks` runs first) |

## When to flag back to the user

Stop and ask, don't guess, when:

- They want the same hook behavior in OpenCode (that's a plugin — confirm before writing).
- They want to commit (always ask before `git commit`).
- An existing skill/agent is being split or renamed and you're unsure.
- The change involves `manifest.yaml` or `profiles/*.yaml` (out of scope for this skill).

If the change is purely additive and matches existing conventions, proceed.
