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

Symlinked targets (installed by `dot install`):

| Tool | Path |
|---|---|
| Claude Code | `~/.claude/skills/<name>/` (user-level) or `.claude/skills/<name>/` (project) |
| OpenCode | `~/.config/opencode/skills/<name>/` (also reads Claude paths via compat) |
| Grok | `~/.grok/skills/<name>/` (also reads Claude paths via compat) |

Directory name **must** match the `name` field in frontmatter, lowercase + digits + hyphens, max 64 chars. OpenCode enforces this with Zod (`^[a-z0-9]+(-[a-z0-9]+)*$`).

## Frontmatter schema

The fields below cover all three tools. Use only the ones you need — every field except `name` and `description` is optional everywhere.

```yaml
---
name: my-skill                 # required by OpenCode; matches dir name
description: ...               # required; trigger text (see below)
compatibility: opencode        # OpenCode only — surfaces skill in OpenCode
license: MIT                   # OpenCode only — optional metadata
metadata:                      # OpenCode only — string-to-string map
  audience: maintainers

# Claude Code adds these (all optional):
when_to_use: ...               # extra trigger phrases; concatenated with description
argument-hint: "[issue]"       # autocomplete hint
arguments: [issue, branch]     # named positional args for $name substitution
allowed-tools: Read Grep Bash  # space-separated or YAML list; pre-approves these tools
disable-model-invocation: false # true = user-only, model can't auto-invoke
user-invocable: true           # false = Claude-only, hidden from / menu
model: inherit                 # sonnet|opus|haiku|<full-id>|inherit
effort: medium                 # low|medium|high|xhigh|max
context: fork                  # run skill in a forked subagent
agent: Explore                 # subagent type when context: fork
paths: ["src/**/*.ts"]         # globs that auto-activate the skill
shell: bash                    # bash (default) or powershell
hooks: { ... }                 # skill-scoped hooks (see hooks.md)
---
```

Grok Build accepts the Claude-Code frontmatter via its compat layer.

### The description field is the trigger

Anthropic's official phrasing is **"Use when…"**. Lead with one sentence stating what the skill is for, then the strongest 2-3 triggers (key file types, the most common user phrases), and optionally a one-clause stack/defer note. Pick a tight handful of triggers — not an exhaustive keyword dump.

**Per-skill budget: aim for ~250-350 chars.** The per-field cap is generous (Claude Code: 1,536 chars `description` + `when_to_use` combined; OpenCode: 1,024 chars `description`), but that's not the binding constraint. Claude Code packs **all installed skill descriptions** into a single "skill listing budget" — default `skillListingBudgetFraction` is **1% of the context window** (~8,000 chars for a 200K window). When the listing overflows, Claude Code drops descriptions for less-used skills and `/doctor` flags it. With ~20 skills installed, that means each one realistically gets ~300-400 chars. A 1,000-char description is the loudest one in the room — and pushes someone else out of the listing.

Anti-patterns that bloat descriptions:
- Listing every file extension (`*.yaml`/`*.yml` referencing `apps/v1`, `networking.k8s.io`, `traefik.io`, …). One representative path is enough.
- Listing every user phrase variant. Pick the 3-4 most distinctive ones.
- Restating the full opinionated stack. That belongs in the body.

Look at `~/.dotfiles/ai/skills/bash/SKILL.md` or `~/.dotfiles/ai/skills/worktrunk/SKILL.md` for tight examples.

### What NOT to put in frontmatter

- **Don't invent fields.** OpenCode rejects unknown frontmatter keys via Zod validation. Claude Code silently ignores them, which is worse.
- **No `tools:`** — that's a subagent field. Use `allowed-tools` for skills.
- **No `mode:`** — that's a subagent field.

## Portability — skills are tool-agnostic by default

Every skill in `~/.dotfiles/ai/skills/` is installed into Claude Code, OpenCode, **and** Grok simultaneously. The model running on any of the three tools will read the same `SKILL.md`. So the body needs to be written for "the agent", not "Claude Code" or "OpenCode".

| Do this | Not this |
|---|---|
| "Use the Read tool to inspect…" | "Use Claude Code's Read tool…" |
| "Run `git diff` via the Bash tool" | "Use the bash tool in OpenCode" |
| "Spawn a subagent for parallel research" | "Use the `Agent` tool" (or "Use the `task` tool") |
| "Edit the file" | "Use `Edit` (or `edit` in OpenCode)" |

The model already knows which tool it's running in and what those tools are named locally — it doesn't need the brand reminder. Use plain English ("the Read tool", "the Bash tool", "the Edit tool", "a subagent") and the model maps it to whatever the local naming is.

**Tool-specific frontmatter is fine** — each tool ignores frontmatter keys it doesn't recognize. Use `compatibility: opencode` to opt into OpenCode's skill surface. Use `allowed-tools: Read Grep Bash` in Claude-shape; OpenCode ignores it harmlessly.

**When a brand-specific reference is unavoidable** (e.g. discussing Claude Code's `/agents` modal, or Grok's `grok inspect` CLI), call out which tool you're talking about. Don't write whole sections of a skill that only work in one tool — that content belongs in dotfiles documentation (`~/.dotfiles/docs/`), not a shared skill.

## Body conventions (this repo's style)

Match the prevailing voice of `~/.dotfiles/ai/skills/*/SKILL.md`:

1. **Open with a mental model paragraph.** One paragraph framing what the tool is and isn't.
2. **Call out the failure mode.** A "the most common AI failure mode is X" sentence works well after the mental model.
3. **Tables for schemas, fenced blocks for examples.** Don't prose-explain a CLI flag if a table will do.
4. **Show, don't tell.** Every "you can do X" claim should be paired with a minimal code block.
5. **No filler.** Skip "In this section we'll cover…". State the thing.

## Progressive disclosure

Keep `SKILL.md` **under 500 lines** (Anthropic guidance; OpenCode and Grok don't enforce but behave the same in practice). When you exceed this, split:

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

- In Claude Code, the env var `${CLAUDE_SKILL_DIR}` resolves to the skill's absolute path regardless of cwd. Use it in `!`...`` shell exec blocks and `allowed-tools` commands.
- In all three tools, **relative paths in markdown** (e.g. `[examples.md](examples.md)`) resolve relative to the skill directory when the agent reads the file.

## Substitution in skill bodies

Both Claude Code and OpenCode support these in the body:

| Token | Expands to |
|---|---|
| `$ARGUMENTS` | All args passed when skill was invoked |
| `$1` … `$9` | Positional args |
| `$ARGUMENTS[N]` | Same as `$N` (Claude Code) |
| `$<name>` | Named arg from `arguments: [name, ...]` (Claude Code) |
| `` !`cmd` `` (inline) or ` ```! `…` ``` ` (block) | Run shell command; output replaces the token before the model sees it |
| `@path/to/file` | File contents inlined (Claude Code memory imports; in OpenCode commands, the body) |

In Claude Code, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`, and `${CLAUDE_SKILL_DIR}` are also available.

## Bundled scripts and resources

Drop helper scripts in `<skill>/scripts/` (or wherever — there's no enforced layout). They're not auto-loaded into context. To use them:

1. Add `allowed-tools: Bash` (or specifically `Bash(./scripts/foo.sh)`) to the frontmatter.
2. Reference the script in the body: `` Run !`${CLAUDE_SKILL_DIR}/scripts/foo.sh $ARGUMENTS` ``.

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

### Claude Code
- Custom slash commands have been **merged into skills**. If you want `/my-thing` to be invocable as a slash command, author it as a skill (the dir name becomes the command). The legacy `~/.claude/commands/` path still works but skills are preferred.
- If a skill and a command share a name, **the skill wins**.
- Plugin skills get a `plugin-name:skill-name` namespace; user/project skills are flat.

### OpenCode
- `name` is validated against `^[a-z0-9]+(-[a-z0-9]+)*$` — directories like `MySkill/` or `my_skill/` will fail to load.
- `compatibility: opencode` is the documented opt-in flag. Skills without it still load but the user-facing labelling differs.
- OpenCode reads Claude paths too — but the dotfiles installer symlinks `ai/skills/` into both, so this rarely matters.

### Grok Build
- Same `SKILL.md` format as Claude (compat). Lives at `~/.grok/skills/<name>/SKILL.md`.
- User-invocable skills auto-expose as `/<skill-name>` slash commands — this is the canonical way to author custom slash commands for Grok.
- Verify with `grok inspect` to confirm Grok picked up the skill from the right source (native `~/.grok/` vs Claude-compat `~/.claude/`).

## Editing an existing skill

Default: extend the existing `SKILL.md`. If the addition is a self-contained subtopic and pushes the file over 500 lines, split it into a sibling reference file and add a decision-tree entry.

If you update the description, double-check Claude Code's 1,536-char cap. The dotfiles installer doesn't validate this — the model will silently truncate at runtime.

## When the skill is done

Tell the user to run `dot install` to refresh symlinks across all three tools. No restart is needed for Claude Code or Grok; OpenCode picks up changes on the next session.
