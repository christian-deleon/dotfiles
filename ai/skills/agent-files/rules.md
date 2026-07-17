# Rules & Instructions

A **rule** is always-loaded context — text the agent reads on every session, regardless of whether it's relevant. Think coding-style guides, project conventions, "always use X library", "never commit .env files". Rules are blunt instruments — every byte costs context for every prompt, so use them sparingly.

The most common AI failure mode is putting skill-shaped content into rules. A rule that says "when editing Terraform files, use the modern HCL syntax" should be a **skill** with a `paths: ["*.tf"]` trigger — that way it only loads when relevant. Rules are for stuff that genuinely applies to every interaction.

## The three loading systems

Each tool loads instructions differently. There's significant overlap but not full equivalence.

| Source path | Claude Code | OpenCode | Grok Build |
|---|---|---|---|
| `~/.claude/CLAUDE.md` | yes (user-level) | yes (compat, env-toggleable) | yes (compat) |
| `~/.claude/rules/*.md` | yes (officially loaded) | no | yes (via `.claude/rules` compat) |
| Project `CLAUDE.md` (walks up to repo root) | yes | yes (compat) | yes (compat) |
| Project `.claude/CLAUDE.md` | yes | no | yes (compat) |
| Project `CLAUDE.local.md` | yes (gitignored) | no | yes (compat) |
| Project `.claude/rules/*.md` | yes | no | yes (compat) |
| Nested `CLAUDE.md` in subdirs | yes (lazy, on file read) | no | partial |
| `~/.config/opencode/AGENTS.md` | no | yes | no |
| Project `AGENTS.md` (walks up) | **no** | yes | yes |
| Project `AGENTS.override.md` | no | no | yes (Codex-style, overrides scoped to dir) |
| `opencode.json` `instructions: [...]` | no | yes | no |
| `~/.grok/AGENTS.md` | no | no | yes |

Key surprise: **AGENTS.md is NOT auto-loaded by Claude Code.** If you want one file that all three tools read, put it at `AGENTS.md` and add a `CLAUDE.md` that does `@AGENTS.md` (or symlink them).

## What this repo does

The dotfiles installer symlinks `~/.dotfiles/ai/rules/*` into `~/.claude/rules/`. For OpenCode, it collects all `ai/rules/**/*.md` paths and writes them into `opencode.json` as `instructions: [...]`. Grok picks up the `~/.claude/rules/*` content via its Claude-compat layer.

```
~/.dotfiles/ai/rules/
├── common/
│   ├── conventions.md
│   └── tone.md
├── work/
│   └── client-x.md
└── personal/
    └── workflow.md
```

Categories are conventional, not enforced — they exist for organization. Subdirectories nest freely.

## Portability — rules apply across all three tools

Rules in `~/.dotfiles/ai/rules/` are installed everywhere:
- Symlinked into `~/.claude/rules/` (Claude reads directly; Grok reads via compat).
- Path-listed in `~/.config/opencode/opencode.json` `instructions: [...]` (OpenCode reads).

So the **content of a rule must be tool-agnostic**. Write rules that apply to "the agent" — not to a specific tool. The rule is loaded on every session regardless of which tool you're using.

A good rule is short, declarative, and brand-free:

```
Always prefer `tofu` over `terraform` in command examples.
Never commit `.env`, `credentials.json`, or `secrets.yaml`.
```

A bad rule pins to a tool:

```
In Claude Code, when using the Read tool, always check file size first.
```

The second one only makes sense in one tool and confuses the others.

## Authoring a rule

```markdown
# (no frontmatter required for plain rules)

Always prefer `tofu` over `terraform` in command examples.

Never commit files named `.env`, `credentials.json`, `secrets.yaml`.

When unsure about a command's destructiveness, ask before running.
```

Plain markdown. No frontmatter, no `name:` field, no trigger string. The agent reads the file as part of its session context.

### Claude Code: `paths:` conditional loading

Claude Code rule files can have frontmatter for **conditional** loading:

```yaml
---
paths: ["src/**/*.ts", "*.tsx"]
---
```

With `paths:`, the rule loads only when Claude reads a matching file in the session. Without it, the rule loads unconditionally at session start. **Use `paths:` aggressively** — unconditional rules cost context tokens on every prompt.

### When to write a rule vs a skill

| Use a rule when | Use a skill when |
|---|---|
| It applies to every interaction (coding style, secret-handling) | It applies only when a specific topic comes up |
| It's a few lines or a short list | It's a body of reference material |
| The model should obey it without thinking | The model should consult it when triggered |

Christian's `~/.dotfiles/ai/rules/` is currently mostly empty — the project uses skills for almost everything. Default to skills.

## Project-level rules

When you want a rule scoped to a single project (not in dotfiles), put it in the project itself:

```
<project>/
├── CLAUDE.md              # checked-in, read by all three tools (Claude direct, OpenCode/Grok compat)
├── AGENTS.md              # checked-in, read by OpenCode + Grok natively (Claude needs @AGENTS.md import)
├── CLAUDE.local.md        # gitignored, read by Claude
└── .claude/
    ├── CLAUDE.md          # alternative location
    └── rules/
        └── foo.md         # loaded by Claude and Grok-compat
```

The portable single-file pattern: write **one** `AGENTS.md` and create a `CLAUDE.md` that's just:

```markdown
@AGENTS.md
```

That covers all three tools with one source.

## Claude Code import syntax

In any `CLAUDE.md` or rule file, you can pull in other files:

```markdown
@docs/architecture.md
@~/.dotfiles/ai/rules/common/conventions.md
```

- Paths resolve relative to the importing file.
- `~/` expands to the home directory.
- Max import depth is 5 hops.
- First time an external import appears, Claude shows an approval dialog.

OpenCode supports a similar inline include mechanism in `opencode.json` `instructions: [...]`:

```json
{
  "instructions": [
    "CONTRIBUTING.md",
    "docs/*.md",
    "https://raw.githubusercontent.com/.../STYLE.md"
  ]
}
```

Globs and remote URLs (5s timeout) are supported. The installer's `generate-opencode-config.sh` populates this automatically from `ai/rules/**/*.md`.

## Per-tool gotchas

### Claude Code
- `~/.claude/rules/*.md` IS officially loaded — this is not a dotfiles convention, it's a Claude Code feature.
- Without `paths:` frontmatter, rules cost tokens on every prompt. Be deliberate.
- `@` imports are relative to the importing file, not cwd.
- AGENTS.md is **not** auto-loaded — use a `CLAUDE.md` that imports it.

### OpenCode
- Doesn't read `~/.claude/rules/` natively. The installer wires rules in via `opencode.json` `instructions: [...]` paths.
- Globs and HTTPS URLs both work in `instructions: [...]`.
- AGENTS.md auto-discovery walks up from cwd to repo root.

### Grok
- Reads `AGENTS.md`, `AGENTS.override.md`, `CLAUDE.md`, `Claude.md`, `CLAUDE.local.md`, and `.claude/rules/` without configuration.
- Hierarchy is Codex-style: walk from repo root down to cwd, one file per directory, override files win per scope, concatenated root-first.
- `~/.grok/AGENTS.md` is the user-level entry — analogous to `~/.claude/CLAUDE.md`.

## Editing rules

Edit the file in `~/.dotfiles/ai/rules/<category>/<name>.md`. Body edits are live via symlink; new rule files need `dot update`. The installer:
- Refreshes the symlink at `~/.claude/rules/<name>.md`
- Regenerates `opencode.json` `instructions: [...]` to include the new path

No tool restart needed; rules are re-read on next session start.

## Minimal canonical example

```markdown
# ~/.dotfiles/ai/rules/common/conventions.md

Always use `rg` instead of `grep` for code search.
Prefer `fd` over `find`.
Default to `tofu` (not `terraform`) in command examples.
When suggesting Kubernetes manifests, target API versions current as of 1.30+.
```

For a Claude-conditional version:

```markdown
---
paths: ["**/*.tf", "**/*.tofu"]
---

In Terraform/OpenTofu files: use `tofu` in commentary, always set `required_version`,
prefer modules over inline resources for anything reused.
```
