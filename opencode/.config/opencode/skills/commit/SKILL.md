---
name: commit
description: >
  Create git commits following the Conventional Commits specification.
  Analyzes staged and unstaged changes, groups them into logical atomic commits,
  and drafts messages using conventional commit types, scopes, and descriptions.
  Activate when the user asks to commit, create commits, or save their work.
compatibility: opencode
---

# Conventional Commits

Create well-structured git commits following the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification.

> **CRITICAL: Always split unrelated changes into separate commits.**
> The default assumption is that a working tree with multiple changed files contains multiple logical changes.
> You must actively justify bundling files together, not the other way around.
> A single commit is only appropriate when **every** changed file contributes to **one** purpose.
> When in doubt, split.

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Purpose | SemVer |
|------|---------|--------|
| `feat` | A new feature or capability | MINOR |
| `fix` | A bug fix | PATCH |
| `docs` | Documentation only (README, comments, docstrings) | - |
| `style` | Formatting, whitespace, semicolons — no logic change | - |
| `refactor` | Code restructuring — no new feature, no bug fix | - |
| `perf` | Performance improvement | - |
| `test` | Adding or correcting tests | - |
| `build` | Build system or external dependencies (npm, pip, cargo) | - |
| `ci` | CI/CD configuration (GitHub Actions, Jenkins, etc.) | - |
| `chore` | Maintenance tasks (deps, tooling, configs) | - |
| `revert` | Reverts a previous commit | - |

### Scope

Optional noun in parentheses describing the section of the codebase:

- `feat(auth):` `fix(api):` `docs(readme):` `refactor(parser):`
- Derive scope from the module, component, or area being changed
- Keep scopes consistent within a repository — check `git log --oneline` for existing conventions

### Description

- Imperative mood: "add feature" not "added feature" or "adds feature"
- Lowercase first letter, no period at the end
- Under 72 characters total (type + scope + description)
- Focus on **why** or **what changed**, not implementation details

### Body

- Separated from description by a blank line
- Wrap at 72 characters
- Explain **what** and **why**, not **how**
- Use when the description alone is insufficient

### Footers

- `BREAKING CHANGE: <explanation>` — signals a breaking API change (MAJOR in SemVer)
- `Refs: #123` or `Closes #456` — link to issues/tickets
- Alternatively use `!` after type/scope for breaking changes: `feat(api)!: remove legacy endpoint`

## Workflow

When asked to commit changes, follow these steps **in order**:

### 1. Assess the Current State

Run these commands in parallel to understand what needs to be committed:

```bash
git status
git diff              # unstaged changes
git diff --cached     # staged changes
git log --oneline -10 # recent commits for style/scope reference
```

### 2. Check for Sensitive Files

**NEVER commit files that likely contain secrets:**

- `.env`, `.env.*` (except `.env.example`)
- `credentials.json`, `secrets.yaml`, `*token*`, `*secret*`
- Private keys (`*.pem`, `*.key`, `id_rsa*`)
- `opencode.json` (may contain resolved secrets — use `.tpl` instead)

If the user explicitly asks to commit these, **warn them** and ask for confirmation.

### 3. Identify Logical Groups — ALWAYS DO THIS

**Default assumption: changes need multiple commits.** Start by treating every changed file as its own potential commit, then merge files together ONLY when they clearly serve the same purpose. Never start from the assumption that everything is one commit.

Follow this process:

1. **List every changed file** and write a one-line summary of what changed in each
2. **Group files by purpose** — ask: "does this file change for the same reason as that one?"
3. **Assign a conventional commit type to each group** — if a group needs two types, split it further
4. **Verify each group** — every file in a group must belong; remove files that don't fit

**Grouping strategy (merge files only when):**

- **Same feature/purpose** — all files contributing to a single feature = one commit
- **Tightly coupled** — a code change and its directly corresponding test = one commit
- **Same type AND scope** — e.g., two related doc updates = one commit

**You MUST split into multiple commits when ANY of these are true:**

- Changes touch unrelated features, bug fixes, or modules
- There are new features mixed with unrelated refactors or cleanups
- Test additions cover different functionality than other code changes
- Documentation updates are not about the code changes present
- Dependency/config updates are mixed with feature or fix work
- Different conventional commit types apply (`feat` + `fix`, `refactor` + `docs`, etc.)

**A single commit is ONLY appropriate when ALL of these are true:**

- Every changed file contributes to exactly one purpose
- A single conventional commit type covers all changes
- You can write one commit message that accurately describes everything without using "and" to join unrelated clauses

### 4. Draft Commit Messages

For each logical group, draft a commit message:

```
<type>(<scope>): <imperative description under 72 chars>
```

Add a body if the change is non-trivial — explain the reasoning, not the diff.

**Good examples:**

```
feat(auth): add OAuth2 login flow with Google provider
fix(api): prevent null pointer when user profile is incomplete
refactor(db): extract connection pooling into dedicated module
docs(readme): add setup instructions for local development
test(auth): add integration tests for token refresh logic
chore(deps): bump express from 4.18.2 to 4.19.0
build(docker): add multi-stage build for smaller production image
ci(actions): add caching for node_modules in CI pipeline
perf(query): add index on users.email for faster lookups
style(lint): apply prettier formatting to src/
feat(api)!: change response envelope from {data} to {result}

BREAKING CHANGE: API consumers must update response parsing
to use `response.result` instead of `response.data`.
```

**Bad examples (avoid these):**

```
update files                     # vague, no type
feat: Changes                    # not imperative, capitalized
Fixed the bug in the thing       # no type, past tense, vague
feat(auth): added new feature.   # past tense, period, redundant
WIP                              # not a meaningful commit
```

### 5. Execute the Plan

**Do not ask for confirmation — just create the commits.** The user trusts you to make good grouping decisions. Proceed directly to creating commits based on your analysis from step 3.

- If you identified multiple logical groups, commit them in dependency order
- If you identified only one logical group, commit it
- Never stall asking "does this grouping look right?" — act on your analysis

### 6. Create the Commits

For each logical group, in dependency order (foundational changes first):

```bash
git add <files>
git commit -m "<type>(<scope>): <description>" -m "<body if needed>"
```

After all commits, run `git status` to verify everything is clean.

### 7. Handle Pre-commit Hook Failures

If a commit fails due to a pre-commit hook (linting, formatting, etc.):

1. Review the hook output to understand what changed
2. If the hook auto-fixed files, stage the fixes and create a **new** commit — do NOT amend
3. If the hook rejected the commit, fix the issue and create a **new** commit
4. Never use `--no-verify` to skip hooks unless the user explicitly asks

## Rules

- **Split by default** — multiple logical changes = multiple commits. Always. No exceptions.
- **Never bundle unrelated changes** — a commit touching auth AND docs AND deps is a red flag; split it
- **Never push** unless the user explicitly asks
- **Never amend** commits you did not create in the current session
- **Never force push** — warn the user if they request it
- **Never create empty commits** — if there are no changes, say so
- **Respect existing conventions** — check `git log` for the repo's existing scope and type patterns
- **Atomic commits** — each commit should be independently meaningful and not break the build
- **Logical order** — when creating multiple commits, order them so each is independently valid (e.g., add dependency before the code that uses it)

### Anti-patterns — DO NOT do these

- Committing all changes as `chore: update files` or `feat: implement changes` — this is always wrong
- Using a single commit with "and" joining unrelated work (e.g., "add auth **and** fix typos **and** update deps")
- Staging everything with `git add .` or `git add -A` without first grouping by purpose
- Treating the entire working tree as one logical unit without analyzing individual file changes
