# Rules & Instructions

A **rule** is always-loaded context — text the agent reads on every session, regardless of whether it's relevant. Think coding-style guides, project conventions, "never commit .env files". Rules are blunt instruments — every byte costs context for every prompt, so use them sparingly.

The most common AI failure mode is putting skill-shaped content into rules. A rule that says "when editing Terraform files, use the modern HCL syntax" should be a **skill** — that way it only loads when relevant. Rules are for stuff that genuinely applies to every interaction.

## How Grok and OpenCode load instructions

| Source path | Grok | OpenCode |
|---|---|---|
| `~/.grok/AGENTS.md` | yes (user-level) | via adapter hop if `dot agent env` linked it |
| `~/.grok/rules/*.md` | yes (flattened from `ai/rules/**`) | no |
| Project `AGENTS.md` (walks repo root → cwd) | yes | yes |
| Project `AGENTS.override.md` | yes (Codex-style, dir-scoped) | no |
| `opencode.json` `instructions: [...]` | no | yes (installer writes `ai/rules/**/*.md` paths) |
| `~/.config/opencode/AGENTS.md` | no | yes (our hop at `~/.grok/AGENTS.md`) |

Grok also still *recognizes* leftover `CLAUDE.md` / `.claude/rules/` when Claude compat is on. This repo forces `[compat.claude] rules/agents = false`. **Don't author `CLAUDE.md` hops.** Foreign repos may still have them — migrate to `AGENTS.md` (`dot agent` already does this).

## What this repo does

`install_ai_grok` flattens `ai/rules/**/*.md` into `~/.grok/rules/<basename>.md` (Grok scans one level, not `rules/common/`). Basenames must be unique.

OpenCode gets the same files as `opencode.json` `instructions: [...]` via `generate-opencode-config.sh`.

```
~/.dotfiles/ai/rules/
├── common/
│   ├── prefer-mcp.md
│   └── no-auto-commit.md
└── …
```

Categories are conventional, not enforced. Subdirectories nest freely in the source tree; only the basename is live for Grok.

## Portability

Write rules for "the agent" — not for a specific runtime. They load on every Grok session and, via the adapter, on OpenCode.

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

For one repo (not in dotfiles), write **`AGENTS.md`** at the project root. Grok and OpenCode both auto-load it. Nested `AGENTS.md` in subdirs accumulate; deeper files win on conflict.

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
- Doesn't read `~/.grok/rules/` natively. The adapter wires rules via `instructions: [...]`.
- Project `AGENTS.md` walks up from cwd to repo root.

## Editing rules

Edit `~/.dotfiles/ai/rules/<category>/<name>.md`. Body edits are live via the flattened symlink. New files need `dot update` (re-flatten + regenerate OpenCode `instructions`).

## Minimal canonical example

```markdown
# ~/.dotfiles/ai/rules/common/conventions.md

Always use `rg` instead of `grep` for code search.
Prefer `fd` over `find`.
Default to `tofu` (not `terraform`) in command examples.
When suggesting Kubernetes manifests, target API versions current as of 1.30+.
```
