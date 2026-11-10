# Rules & Instructions

A **rule** is always-loaded context — text the agent reads on every session, regardless of whether it's relevant. Think coding-style guides, project conventions, "never commit .env files". Rules are blunt instruments — every byte costs context for every prompt, so use them sparingly.

The most common AI failure mode is putting skill-shaped content into rules. A rule that says "when editing Terraform files, use the modern HCL syntax" should be a **skill** — that way it only loads when relevant. Rules are for stuff that genuinely applies to every interaction.

## How the harnesses load instructions

| Source path | Grok | OpenCode | Claude Code |
|---|---|---|---|
| `~/.grok/AGENTS.md` | yes (user-level; `dot agent env` link) | no | no |
| `~/.grok/rules/*.md` | yes (flattened from `ai/rules/**`) | no | no |
| `~/.config/opencode/AGENTS.md` | no | yes (`dot agent env` link) | no |
| `opencode.json` `instructions: [...]` | no | yes (installer writes `ai/rules/**/*.md` paths) | no |
| `~/.claude/CLAUDE.md` | no | no | yes (user-level; `dot agent env` link) |
| `~/.claude/rules/*.md` | no (compat off) | no | yes (flattened from `ai/rules/**`) |
| Project `AGENTS.md` (walks repo root → cwd) | yes | yes | yes |
| Project `AGENTS.override.md` | yes (Codex-style, dir-scoped) | no | no |

Claude loads `~/.claude/rules/` files with no `paths:` frontmatter in every session. **Don't author a project `CLAUDE.md`.** If one sits beside `AGENTS.md`, Claude Code reads only the `CLAUDE.md`. Foreign repos may still have them — migrate to `AGENTS.md` (`dot agent` already does this).

## What this repo does

`install_ai_grok` and `install_ai_claude` flatten `ai/rules/**/*.md` into `~/.grok/rules/<basename>.md` and `~/.claude/rules/<basename>.md` (Grok scans one level, not `rules/common/`). Basenames must be unique. `install_ai_opencode` lists the same files in `opencode.json` `instructions: [...]` via `generate-opencode-config.sh`.

```
~/.dotfiles/ai/rules/
├── common/
│   ├── prefer-mcp.md
│   └── no-auto-commit.md
└── …
```

Categories are conventional, not enforced. Subdirectories nest freely in the source tree; only the basename is live for Grok and Claude.

## Portability

Write rules for "the agent" — not for a specific runtime. They load on every session in all three harnesses.

A good rule is short, declarative, and brand-free:

```
Always prefer `tofu` over `terraform` in command examples.
Never commit `.env`, `credentials.json`, or `secrets.yaml`.
```

A bad rule pins to a runtime:

```
In Grok, when using the Read tool, always check file size first.
```

## Authoring a rule

```markdown
# (no frontmatter required)

Always prefer `tofu` over `terraform` in command examples.

Never commit files named `.env`, `credentials.json`, `secrets.yaml`.

When unsure about a command's destructiveness, ask before running.
```

Plain markdown. No `name:` field, no trigger string.

### When to write a rule vs a skill

| Use a rule when | Use a skill when |
|---|---|
| It applies to every interaction (coding style, secret-handling) | It applies only when a specific topic comes up |
| It's a few lines or a short list | It's a body of reference material |
| The model should obey it without thinking | The model should consult it when triggered |

This repo's `ai/rules/` is intentionally small — skills do almost everything. Default to skills.

## Project-level rules

For one repo (not in dotfiles), write **`AGENTS.md`** at the project root. All three harnesses auto-load it. Nested `AGENTS.md` in subdirs accumulate; deeper files win on conflict.

Don't add a `CLAUDE.md` that `@AGENTS.md`. If a foreign project already has `CLAUDE.md` and no `AGENTS.md`, leave it — Grok still recognizes the filename even with Claude *compat dirs* off (generic top-level `CLAUDE.md` stays recognized). Prefer `AGENTS.md` for anything new.

OpenCode can also list extra files in `opencode.json` `instructions`:

```json
{
  "instructions": [
    "CONTRIBUTING.md",
    "docs/*.md"
  ]
}
```

Globs and remote URLs (5s timeout) work. The installer already injects `ai/rules/**/*.md`; don't duplicate those by hand.

## Per-tool gotchas

### Grok
- Home rules: `~/.grok/rules/*.md` then `~/.grok/AGENTS.md`.
- Project: every directory from repo root to cwd; `AGENTS.md` / `AGENTS.override.md`.
- Flattened install — two source files named `conventions.md` in different categories collide.

### OpenCode
- Rules arrive via `instructions: [...]`, not a rules dir.
- Project `AGENTS.md` walks up from cwd to repo root.

### Claude Code
- Home rules: `~/.claude/rules/*.md` then `~/.claude/CLAUDE.md`. Same flattening collision as Grok.

## Editing rules

Edit `~/.dotfiles/ai/rules/<category>/<name>.md`. Body edits are live via the flattened symlinks / `instructions` paths. New files need `dot update` (re-flatten + regenerate OpenCode `instructions`).

## Minimal example

```markdown
# ~/.dotfiles/ai/rules/common/conventions.md

Always use `rg` instead of `grep` for code search.
Prefer `fd` over `find`.
Default to `tofu` (not `terraform`) in command examples.
When suggesting Kubernetes manifests, target API versions current as of 1.30+.
```
