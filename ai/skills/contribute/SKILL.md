---
name: contribute
description: >
  Guide contributions to upstream open-source GitHub projects. Reads project
  guidelines (CONTRIBUTING.md, PR templates, git log), adapts to the project's
  conventions, and creates well-formed pull requests using gh CLI. Activate when
  the user mentions contributing to a public GitHub project, submitting upstream,
  or opening a PR.
compatibility: opencode
---

# Contributing to Upstream OSS Projects

Guide for contributing changes to public open-source GitHub repositories. Assumes the fork is already cloned and remotes are configured.

## 1. Discover Project Conventions

**Before writing any code or commits**, read the project's rules. Run these in parallel:

```bash
# Contribution guidelines (check both locations)
cat CONTRIBUTING.md 2>/dev/null || cat .github/CONTRIBUTING.md 2>/dev/null
cat CODE_OF_CONDUCT.md 2>/dev/null

# PR template (check all common locations)
cat .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null || cat .github/pull_request_template.md 2>/dev/null
ls .github/PULL_REQUEST_TEMPLATE/ 2>/dev/null

# Commit message style from recent history
git log --oneline -20

# Check for DCO/sign-off requirements
grep -i "sign-off\|DCO\|developer certificate" CONTRIBUTING.md .github/CONTRIBUTING.md 2>/dev/null

# Detect test/lint tooling
ls Makefile tox.ini pyproject.toml package.json Cargo.toml go.mod 2>/dev/null
```

**Summarize findings to the user** before proceeding:

- Commit message convention (Conventional Commits, Angular, plain imperative, other)
- PR template sections to fill out
- Required checks (tests, linting, DCO sign-off)
- Any special contribution rules (e.g., "one commit per PR", "rebase only", "squash on merge")

## 2. Branch Preparation

### Sync with upstream

```bash
git fetch upstream
git checkout -b <branch-name> upstream/<default-branch>
```

### Branch naming

Check if the project has a naming convention in CONTRIBUTING.md or by inspecting existing branches. If none, use:

```
<type>/<short-description>
```

Examples:

```
fix/null-pointer-empty-input
feat/add-json-output-format
docs/clarify-auth-setup
```

Keep it lowercase, hyphen-separated, concise.

## 3. Adapt to the Project's Commit Convention

**Project conventions take priority over personal preferences.**

### Detection strategy

1. Read CONTRIBUTING.md for explicit commit message rules
2. Run `git log --oneline -20` to observe existing patterns
3. Look for tooling hints (`.commitlintrc`, `commitizen` in package.json, `.conventional-commit` config)

### Apply what you find

| Detected convention | What to do |
|---|---|
| Conventional Commits (`feat:`, `fix:`, etc.) | Follow their types, scopes, and formatting exactly |
| Angular-style (`feat(scope):`) | Same as Conventional Commits with required scopes |
| Plain imperative (`Add feature`, `Fix bug`) | Match their casing, tense, and line length |
| Ticket prefix (`[PROJ-123] Add feature`) | Include the ticket/issue reference in the format they use |
| No detectable convention | Fall back to Conventional Commits (use the `commit` skill) |

**Always match the project's patterns** for:

- Capitalization (lowercase vs. sentence case)
- Tense (imperative vs. past)
- Scope usage and naming
- Line length limits
- Footer format for issue references

## 4. Pre-PR Checklist

Before creating the PR, verify everything is in order:

### Code quality

- [ ] Changes are **focused** — one logical concern per PR
- [ ] No unrelated changes (formatting, refactors, dependency bumps)
- [ ] No debugging artifacts (`console.log`, `print()`, `TODO`, commented-out code)
- [ ] Code follows the project's existing style (indentation, naming, patterns)

### Tests and CI

Detect and run the project's test/lint commands:

```bash
# Common patterns — run whatever applies
make test          # Makefile projects
make lint
npm test           # Node.js
npm run lint
cargo test         # Rust
go test ./...      # Go
pytest             # Python
tox
```

If you cannot determine how to run tests, check:

- `CONTRIBUTING.md` for test instructions
- `Makefile` targets
- `package.json` scripts section
- CI config (`.github/workflows/`, `.circleci/`, `.travis.yml`)

### Commits

- [ ] Commits are clean and atomic (each independently meaningful)
- [ ] Commit messages follow the project's convention (see step 3)
- [ ] If DCO is required, commits include `Signed-off-by` (use `git commit --signoff`)

### Rebase on latest

```bash
git fetch upstream
git rebase upstream/<default-branch>
```

Resolve any conflicts before proceeding. If the rebase is complex, inform the user.

## 5. Create the Pull Request

### Push to fork

```bash
git push -u origin <branch-name>
```

**Always push to `origin` (the fork), never to `upstream`.**

### Fill out the PR

If a **PR template** was found in step 1, fill out every section. Do not delete template sections — fill them in or write "N/A" if not applicable.

If **no template** exists, structure the PR body as:

```markdown
## Summary
<1-3 sentences: what this PR does and why>

## Motivation
<Why is this change needed? Link to issue if applicable>

## Changes
<Bullet list of what changed>

## Testing
<How you verified the changes work>
```

### Create with gh CLI

```bash
gh pr create \
  --title "<title matching project convention>" \
  --body "$(cat <<'EOF'
<PR body here>
EOF
)"
```

### Link issues

Use the project's preferred syntax in the PR body:

- `Closes #123` — auto-closes the issue on merge
- `Fixes #123` — same as Closes
- `Refs #123` — references without closing

### Present the PR plan first

**Always show the user** the complete PR (title, body, target branch) **before** running `gh pr create`. Let them adjust before submitting.

### After creation

Return the PR URL so the user can review it in the browser.

## Rules

- **Never push to upstream** — always push to `origin` (the fork)
- **Never force push** unless the user explicitly asks (e.g., after a rebase)
- **Never skip CI or tests** — run them before opening the PR
- **Never delete PR template sections** — fill them in or mark N/A
- **Respect the code of conduct** — keep PR descriptions professional and constructive
- **DCO sign-off** — if the project requires it, remind the user and use `--signoff`
- **One concern per PR** — if the user's changes span multiple unrelated things, suggest splitting into separate PRs
- **Present before submitting** — always show the PR plan for user confirmation before creating it
- **Follow project conventions** — when in doubt, match what existing contributors do
