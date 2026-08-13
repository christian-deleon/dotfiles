# Skills

A **skill** is a directory containing a `SKILL.md` (plus optional companion files). The model loads the frontmatter description into its tool catalog at startup and lazily reads the body only when the description matches the conversation. This is "progressive disclosure" — keep `SKILL.md` lean and put depth in companion files.

The most common AI failure mode is treating `SKILL.md` as a single-file manual. When a skill's body grows past ~500 lines, split: keep triggers, decision tree, and universal rules in `SKILL.md`; move per-topic depth into sibling `.md` files that `SKILL.md` instructs the agent to read on demand. See this skill (`agent-files/`) for the canonical layout.

## Where skills live

Source of truth in this repo:

```
~/.dotfiles/ai/skills/<name>/
├── SKILL.md          # required entry point
├── <topic>.md        # optional reference files
├── examples/         # optional templates / examples
└── scripts/          # optional bundled scripts (executable via Bash)
```

Installed by `install_ai_grok` to `~/.grok/skills/<name>/`. OpenCode sees the same tree via a directory symlink (`~/.config/opencode/skills` → `~/.grok/skills`).

Directory name **must** match the `name` field in frontmatter, lowercase + digits + hyphens, max 64 chars. OpenCode enforces `^[a-z0-9]+(-[a-z0-9]+)*$`. Grok normalizes spaces and underscores to hyphens if you omit `name` (it then uses the directory name).

## Frontmatter schema

Grok's official skill fields (user guide 08-skills). Use only the ones you need — every field except `name` and `description` is optional. Multi-word keys are **kebab-case**.

```yaml
---
name: my-skill                 # identifier; must match dir name
description: ...               # trigger text (see below)
compatibility: opencode        # keep this so the OpenCode adapter surfaces the skill
license: MIT                   # optional metadata (also recognized by OpenCode)
metadata:                      # optional string-to-string map (also OpenCode)
  audience: maintainers

# Grok official (OpenCode ignores these extra keys):
when-to-use: ...               # extra trigger phrases, kept separate from description
argument-hint: "[issue]"       # slash-command autocomplete hint
allowed-tools: Read Grep Bash  # YAML list or comma/space-separated; pre-approves tools
disable-model-invocation: false # true = user-only slash command; model cannot auto-invoke
user-invocable: true           # false = hide from slash menu (model can still invoke)
model: grok-build              # model override for running the skill
effort: medium                 # reasoning-effort override
---
```

OpenCode **only recognizes** `name`, `description`, `license`, `compatibility`, `metadata`. Unknown keys are **ignored** (current OpenCode docs — it used to Zod-fail). Extra Grok fields on a shared `SKILL.md` are therefore safe.

Grok also documents `metadata.author` and `metadata.short-description` for display. Fields like `context: fork`, `agent:`, `paths:`, `shell:`, and skill-scoped `hooks:` are not in Grok's official table — don't invent them unless you've confirmed they work with `grok inspect`.

### The description field is the trigger

Lead with one sentence stating what the skill is for, then the strongest 2–3 triggers (key file types, the most common user phrases), and optionally a one-clause stack/defer note. Pick a tight handful of triggers — not an exhaustive keyword dump. Grok matches the user's prompt against `description` and `when-to-use` for automatic invocation.

**Per-skill budget: aim for ~250–350 chars.** OpenCode's hard cap is **1,024 chars** on `description`. Grok has no documented listing-budget; the short budget is still the right craft — a 1,000-char description crowds the catalog and dilutes the trigger.

Anti-patterns that bloat descriptions:
- Listing every file extension (`*.yaml`/`*.yml` referencing `apps/v1`, `networking.k8s.io`, `traefik.io`, …). One representative path is enough.
- Listing every user phrase variant. Pick the 3–4 most distinctive ones.
- Restating the full opinionated stack. That belongs in the body.

Look at `~/.dotfiles/ai/skills/bash/SKILL.md` or `~/.dotfiles/ai/skills/worktrunk/SKILL.md` for tight examples.

### What NOT to put in frontmatter

- **Don't invent fields.** Stick to the Grok table above plus the OpenCode four (`license`, `compatibility`, `metadata`).
- **No `tools:`** — that's a subagent field. Use `allowed-tools` for skills.
- **No `mode:`** — that's a subagent field.

## Portability — write the body for Grok

Every skill in `~/.dotfiles/ai/skills/` is what Grok loads. OpenCode reads the same files via the adapter. Write the body for "the agent":

| Do this | Not this |
|---|---|
| "Use the Read tool to inspect…" | "Use Grok's Read tool…" |
| "Run `git diff` via the Bash tool" | "Use the bash tool in OpenCode" |
| "Spawn a subagent for parallel research" | "Use the `spawn_subagent` tool" (unless the skill is Grok-specific) |
| "Edit the file" | "Use `Edit` (or `search_replace` in Grok)" |

The model already knows which runtime it's in. Use plain English ("the Read tool", "the Bash tool", "the Edit tool", "a subagent").

**Tool-specific frontmatter is fine.** `compatibility: opencode` opts into OpenCode's skill surface. `allowed-tools: Read Grep Bash` is Grok-shaped; OpenCode ignores it.

**When a brand-specific reference is unavoidable** (Grok's `grok inspect`, OpenCode's `@name` / Tab cycle), call it out. Don't write whole sections of a skill that only work in OpenCode — that content belongs in `~/.dotfiles/docs/`.

## Body conventions (this repo's style)

Match the prevailing voice of `~/.dotfiles/ai/skills/*/SKILL.md`:

1. **Open with a mental model paragraph.** One paragraph framing what the tool is and isn't.
2. **Call out the failure mode.** A "the most common AI failure mode is X" sentence works well after the mental model.
3. **Tables for schemas, fenced blocks for examples.** Don't prose-explain a CLI flag if a table will do.
4. **Show, don't tell.** Every "you can do X" claim should be paired with a minimal code block.
5. **No filler.** Skip "In this section we'll cover…". State the thing.

## Progressive disclosure

Keep `SKILL.md` **under 500 lines**. When you exceed this, split:

```
my-skill/
├── SKILL.md          # triggers + decision tree + universal rules (lean)
├── advanced.md       # the long-tail content
├── examples.md       # extended examples
└── scripts/
    └── helper.sh     # executable, invoked via Bash if allowed-tools permits
```

`SKILL.md` then instructs the agent: "For advanced X, read `advanced.md`. For examples, read `examples.md`." The agent loads those only when needed.

### Path resolution for companion files

**Relative paths in markdown** (e.g. `[examples.md](examples.md)`) resolve relative to the skill directory when the agent reads the file. Prefer that over env-var paths.

## Substitution in skill bodies

When the user invokes `/skill-name args`, Grok passes the args after the name. These tokens are useful in user-invocable skills (and in leftover command templates):

| Token | Expands to |
|---|---|
| `$ARGUMENTS` | All args passed when the skill was invoked |
| `$1` … `$9` | Positional args |
| `` !`cmd` `` (inline) or ` ```! `…` ``` ` (block) | Run shell; output replaces the token before the model sees it |

Don't depend on Claude-only tokens (`${CLAUDE_SKILL_DIR}`, `$ARGUMENTS[N]`, named `$<name>` from `arguments:`). Use a relative path or an absolute `~/.dotfiles/ai/skills/<name>/scripts/…` path for bundled scripts.

## Bundled scripts and resources

Drop helper scripts in `<skill>/scripts/` (or wherever — there's no enforced layout). They're not auto-loaded into context. To use them:

1. Add `allowed-tools: Bash` (or a tighter glob) to the frontmatter.
2. Reference the script in the body by path: `` Run `~/.dotfiles/ai/skills/<name>/scripts/foo.sh $ARGUMENTS` ``.

Keep scripts focused — a skill should be a self-contained capsule, not a Trojan horse for a full CLI tool. If a script grows complex, move it to `~/.dotfiles/scripts/` and have the skill just call it by name.

## Minimal canonical example

See [`examples/skill.template.md`](examples/skill.template.md). The shortest valid skill:

```markdown
---
name: summarize-diff
description: Summarize uncommitted git changes. Use when the user asks what changed, wants a commit message, or asks to review their diff.
compatibility: opencode
---

!`git diff HEAD`

Summarize the changes above in two or three bullets.
```

## Per-tool gotchas

### Grok Build
- Official `SKILL.md` format. Lives at `~/.grok/skills/<name>/SKILL.md`.
- User-invocable skills auto-expose as `/<skill-name>` — this is the canonical slash-command path.
- Same-named local / repo / user skills override bundled copies. Collisions with built-ins get a qualified name (`/user:commit`).
- Verify with `grok inspect` (source should be `user`, path under `~/.grok/skills/` or the symlink into `ai/skills/`).
- Discovery also scans `.agents/skills/` and (if compat is on) `.claude/skills/`. This repo has Claude compat **off**; don't rely on those paths.

### OpenCode (adapter)
- Recognized keys: `name`, `description`, `license`, `compatibility`, `metadata`. Extra keys are ignored.
- `name` must match `^[a-z0-9]+(-[a-z0-9]+)*$` and the directory name.
- `description` hard cap 1,024 chars.
- `compatibility: opencode` is the documented opt-in flag.
- Discovers `~/.config/opencode/skills/` (our dir symlink), plus `.opencode/skills/`, `.agents/skills/`, and leftover `.claude/skills/` if present.

## Editing an existing skill

Default: extend the existing `SKILL.md`. If the addition is a self-contained subtopic and pushes the file over 500 lines, split it into a sibling reference file and add a decision-tree entry.

If you update the description, stay under OpenCode's 1,024-char cap. The installer doesn't validate this.

## When the skill is done

Body edits are live via symlink. New skills: `dot update`. Restart the session if you changed a skill *description*.
