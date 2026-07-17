---
name: wtc
description: User-only /wtc — spawn a sibling tmux+worktree agent via shell wtc. User triggers only (or says "wtc that"). Agents may suggest a /wtc line for side bugs/features but must never auto-run.
compatibility: opencode
argument-hint: "[branch] [bug/task prompt...]"
disable-model-invocation: true
user-invocable: true
---

# /wtc — spawn a parallel fix agent

`/wtc` is the **user-gated** way to hand a bug or task to a fresh agent in a new worktree + tmux window. It wraps the shell function `wtc` from `functions.d/worktrunk.sh`: create (or switch to) a worktree, open a `tav` layout, launch `$AI_TOOL` with an initial prompt, jump to that window.

**Two ways this gets used:**

1. **You run `/wtc` yourself** (or say "wtc that" / "spawn a fix agent") — this skill runs and executes.
2. **An agent finds side work** while on another task — it may *suggest* a ready `/wtc …` line (see the always-on rule), but must not execute until you trigger it.

**Authorization for this turn only.** Loading this skill means the user invoked `/wtc` (or explicitly ordered a spawn). That is the only permission you need — do not re-ask. Outside of that, never run `wtc` / `wta` / `wtaa`.

The most common failure mode is treating "we found a bug" as a reason to spawn. It is not — **suggest** `/wtc …` and wait. Another failure mode is a thin prompt ("fix the bug") that leaves the child agent with no context — always pack the handoff into `-p`.

## Arguments

`$ARGUMENTS` is freeform. Parse it as:

| Shape | Meaning |
|---|---|
| `fix/foo bar baz…` | Branch = first token if it looks like a branch (`type/slug`, or contains `/`). Rest = seed for the child prompt. |
| `bar baz…` (no branch) | Invent a short branch: `fix/<kebab-slug>` from the task (or `feat/` / `chore/` when clearly not a bug). Rest = seed for the child prompt. |
| empty | Derive both branch and prompt entirely from this conversation's current problem. |

Branch names should be short, filesystem-safe after sanitize (`/` → `-` in the window name), and descriptive: `fix/auth-null-session`, not `fix/thing`.

Optional base branch is rare; only pass a second positional base to shell `wtc` if the user named one explicitly (e.g. `/wtc hotfix/login production …`).

## Workflow

### 1. Build the child prompt

Write a self-contained prompt the child can act on with **no** access to this conversation. Prefer:

```text
## Task
<what to fix or build — one tight paragraph>

## Context
- <file:line or path anchors>
- <error text, failing test, or observed behavior — exact quotes>
- <anything already ruled out or confirmed>

## Done when
<acceptance check — what "fixed" looks like>
```

Use `$ARGUMENTS` plus recent conversation findings. Do not invent file paths or error text you have not seen — if context is thin, still spawn, but mark unknowns ("suspected — not confirmed") rather than guessing.

### 2. Preconditions

Before running:

- Cwd must be inside the target git repo (project is resolved from cwd).
- `$AI_TOOL` / `$AI_TOOL_RESUME` must be set (else `wtc` errors — tell the user to run `dot ai-tool`).
- Shell agents often lack interactive functions — source before calling:

```bash
source "$HOME/.dotfiles/functions.d/worktrunk.sh"
```

### 3. Run `wtc`

One shot — do not dry-run, do not ask for confirmation after the user already ran `/wtc`:

```bash
source "$HOME/.dotfiles/functions.d/worktrunk.sh"
wtc -p '<child prompt, single-quoted / properly escaped>' '<branch>'
```

Notes:

- `-p` / `--prompt` is required whenever you have a task description (almost always).
- `wtc` uses `wt switch --create … --no-cd` for new branches (or plain `switch --no-cd` if the branch already exists), then creates the tmux window and **switches the client** to it. That client jump is intentional — do not try to suppress it.
- A real worktree + branch is created. This is not a simulation.

### 4. Report back

In this parent session, state briefly:

- Branch and worktree path
- Tmux `session:window`
- That the child was launched with the prompt (one-line summary, not a full re-dump)

Do not keep working the child's task here unless the user asks. The parallel agent owns it.

## Examples

```text
/wtc fix/session-null Null deref in auth when session expires after idle; see auth/session.go:142
```

```text
/wtc the flaky test in pkg/api/retry_test.go fails under -race — isolate and fix
```

```text
/wtc
```

(with conversation context supplying the bug)

## Do not

- Run `wtc` / `wta` / `wtaa` just because you noticed side work — **suggest** a `/wtc …` line instead; only execute when this skill was invoked or the user explicitly ordered it this turn.
- Spawn into a different repo than the user's current project without an explicit path/repo ask.
- Pass an empty `-p` when you have conversation context to hand off.
- Clean up the worktree afterward unless asked (`wt remove` is a separate explicit action).

