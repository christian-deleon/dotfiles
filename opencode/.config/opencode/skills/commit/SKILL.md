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

### 3. Identify Logical Groups

Analyze all changes and group them into **atomic, logical commits**. Each commit should represent one coherent unit of work:

**Grouping strategy:**

- **By feature/purpose** — all files contributing to a single feature = one commit
- **By type** — separate docs from code changes, tests from implementation
- **By scope** — changes to different modules/components may warrant separate commits
- **Config vs code** — configuration changes often deserve their own commit

**Signs you need multiple commits:**

- Changes span unrelated features or bug fixes
- There are both new features and unrelated refactors
- Test additions are for different functionality than code changes
- Documentation updates are unrelated to code changes
- Dependency updates are mixed with feature work

**Signs a single commit is appropriate:**

- All changes serve one purpose (a single feature, fix, or refactor)
- Test changes directly correspond to the code changes
- Documentation updates describe the code changes in the same commit

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

### 5. Confirm with the User

Present the commit plan:

- List each proposed commit with its message and the files it includes
- If there is only one logical commit, proceed without asking
- If there are multiple commits, present the grouping and ask for confirmation
- Let the user adjust groupings or messages before proceeding

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

- **Never push** unless the user explicitly asks
- **Never amend** commits you did not create in the current session
- **Never force push** — warn the user if they request it
- **Never create empty commits** — if there are no changes, say so
- **Respect existing conventions** — check `git log` for the repo's existing scope and type patterns
- **Atomic commits** — each commit should be independently meaningful and not break the build
- **Logical order** — when creating multiple commits, order them so each is independently valid (e.g., add dependency before the code that uses it)
