---
name: wtc
description: Spawn sibling tmux+worktree agent(s) via shell wtc when the user explicitly approves (slash /wtc, "wtc that", "spawn a fix agent", "one for each", …). Builds a full -p handoff; always -n so focus is not stolen. Without approval, only suggest /wtc lines.
compatibility: opencode
argument-hint: "[branch] [message…] | each: … | (empty = from context)"
user-invocable: true
---

# /wtc — spawn a parallel fix agent

`/wtc` hands a bug or task to a fresh agent in a new worktree + tmux window. It
wraps the shell function `wtc` from `functions.d/worktrunk.sh`: create (or switch
to) a worktree, open a `tav` layout, launch `$AI_TOOL` with an initial prompt.

**Interactive shell `wtc` jumps by default** (what humans want when they type it).
**Agent invocations must always pass `-n` / `--no-switch`** so the new window is
created without stealing focus from the user's current window.

**Two ways this gets used:**

1. **User runs `/wtc`** (or says "wtc that" / "spawn a fix agent" / "one worktree
   for each") — this skill runs and executes. That **is** approval for this turn.
2. **You find side work** while on another task — *suggest* ready `/wtc …`
   line(s) (see always-on rule `no-auto-wtc`); do **not** execute until they
   approve.

**Authorization for this turn only.** User slash `/wtc` or an explicit natural-
language spawn order this turn is the only permission you need — do not re-ask.
Outside of that, never run `wtc` / `wta` / `wtaa`.

The most common failure mode is treating "we found a bug" as a reason to spawn.
It is not — **suggest** `/wtc …` and wait. Another is a thin prompt ("fix the
bug") that leaves the child with no context — always pack the handoff into `-p`.
A third is bare `wtc` without `-n` (steals focus). A fourth is **keeping ownership
after spawn**: still implementing the child's task, or treating child work as open
on *this* session's checklist when the user asks "is everything resolved?" —
spawn transfers accountability; see **Ownership after spawn**.

## Arguments — how to pass a message

`$ARGUMENTS` is freeform text after `/wtc`. That text **is** the message seed
(plus optional branch). There is no separate flag in the slash command — the
shell form uses `-p` under the hood; you build that from args + conversation.

| What you type | What happens |
|---|---|
| `/wtc fix/session-null Null deref at auth/session.go:142 after idle` | Branch = `fix/session-null`. Message seed = everything after the branch. Expanded with conversation context into full `-p` handoff. |
| `/wtc Null deref at auth/session.go:142 after idle` | No branch token → invent `fix/<kebab-slug>` from the message. Rest is the seed. |
| `/wtc` | Empty args → derive branch + full prompt from the **current** problem in this conversation. |
| `/wtc each of the four we found` / `/wtc one for each` / `/wtc` after you listed N issues and said spawn all | **Multi-spawn** — one worktree + agent per item (see below). |
| `/wtc` + a numbered/bulleted list of tasks in `$ARGUMENTS` | Multi-spawn — one per list item. |

**Branch token rule:** first token is a branch only if it looks like one
(`type/slug`, or contains `/`). Otherwise the whole string is message seed.

Branch names: short, descriptive (`fix/auth-null-session`, not `fix/thing`).
Window name = branch with `/` → `-`.

Optional base branch is rare; only pass shell `wtc`'s second positional base if
the user named one explicitly (e.g. `/wtc hotfix/login production …` for a
single spawn).

### Multi-spawn (N worktrees)

When the user wants **one agent per issue** — e.g. four discoveries, "create a
worktree for each", "spawn all of these", or a multi-item list in `$ARGUMENTS`:

1. Build an ordered list of tasks from `$ARGUMENTS` **and/or** the conversation
   (what you already suggested, what they just listed).
2. For **each** task, invent a distinct branch (`fix/…` / `feat/…`) and a full
   self-contained `-p` prompt (same template as single spawn). Do not put all
   four bugs into one prompt.
3. Run `wtc -n` **once per task**, sequentially. Focus never moves; the user
   stays on their current window the whole time.
4. Report a compact table: branch → window → one-line task.

If the list is ambiguous (can't tell whether two bullets are one task or two),
ask once; otherwise act.

## Workflow

### 1. Build the child prompt(s)

Each child gets a self-contained prompt with **no** access to this conversation:

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

Sources, in order: `$ARGUMENTS` message seed → recent conversation findings for
that item. Do not invent file paths or error text you have not seen — mark
unknowns ("suspected — not confirmed") rather than guessing.

### 2. Preconditions

- Cwd must be inside the target git repo (project is resolved from cwd).
- `$AI_TOOL` / `$AI_TOOL_RESUME` must be set (else `wtc` errors — tell the user
  to run `dot ai-tool`).
- Shell agents often lack interactive functions — source once before the first
  call:

```bash
source "$HOME/.dotfiles/functions.d/worktrunk.sh"
```

### 3. Run `wtc` (once, or once per task)

Do not dry-run. Do not re-confirm after the user already approved this turn.

**Always pass `-n` / `--no-switch`.** Interactive shell `wtc` (no flag) jumps by
default for humans; agent use must not.

**Single:**

```bash
source "$HOME/.dotfiles/functions.d/worktrunk.sh"
wtc -n -p '<full child prompt>' '<branch>'
```

**Multi** — same, looped; distinct branch + prompt each time:

```bash
source "$HOME/.dotfiles/functions.d/worktrunk.sh"
wtc -n -p '<prompt for item 1>' 'fix/slug-one'
wtc -n -p '<prompt for item 2>' 'fix/slug-two'
# …
```

Notes:

- `-p` is required whenever there is a task description (almost always).
- `-n` / `--no-switch` is required for every call from this skill.
- Escape quotes carefully so the shell sees one prompt string.
- `wtc` creates a real worktree + branch and a new tmux window; with `-n` it
  does **not** switch the client to that window.

### 4. Report back

Briefly list each spawn:

- Branch and worktree path
- Tmux `session:window` (created; focus stayed put)
- One-line task summary (not a full re-dump of `-p`)

Then stop. The user switches when ready (`wta <branch>`, tmux window picker, etc.).

## Ownership after spawn

**Once `wtc` successfully creates a worktree + agent for a task, that task is no
longer this session's problem.** Parallel agents own their items end-to-end
(implement, verify, residual report). The parent only owns work still on **this**
branch / worktree.

| Do | Don't |
|---|---|
| Answer "is everything resolved?" for **this** session's scope only | List spawned branches as open blockers on this session's done checklist |
| Continue the parent's original task | Implement, re-debug, or re-verify the child's task here |
| Hand off again only if the user pulls the issue back or asks you to work it | Poll child worktrees, merge their status into "are we done?", or restate their bugs as yours |

Exceptions — only when the user **explicitly** asks this session to: resume the
child's task, check that agent, merge that branch, or re-own the issue.

Spawning is a clean cut: full `-p` handoff goes out; accountability does not stay
behind as dual ownership.

## Examples

**Message + branch (single):**
```text
/wtc fix/session-null Null deref in auth when session expires after idle; see auth/session.go:142
```

**Message only (agent invents branch):**
```text
/wtc flaky test in pkg/api/retry_test.go fails under -race — isolate and fix
```

**Empty (current problem from chat):**
```text
/wtc
```

**Multi — spawn one worktree per discovery:**
```text
/wtc one worktree for each of the four side issues we found
```

```text
/wtc each:
1. null deref auth/session.go:142 after idle
2. race in pkg/api/retry_test.go
3. missing index on users.email in migrations
4. docs lie about --dry-run in cmd/root.go
```

**Agent suggestion style** (do not execute until user triggers — rule):
```text
Want parallel agents? For example:
/wtc fix/session-null Null deref auth/session.go:142 after idle
/wtc fix/retry-race flaky -race in pkg/api/retry_test.go
```
Or one multi-trigger:
```text
/wtc one for each of the four above
```

## Do not

- Run `wtc` / `wta` / `wtaa` just because you noticed side work — **suggest**
  `/wtc …` line(s) instead; only execute when this skill was invoked or the user
  explicitly ordered a spawn this turn.
- Run bare `wtc` without `-n` from this skill — that steals the user's focus.
- Cram multiple unrelated bugs into a **single** child prompt when the user
  asked for one worktree each — split.
- Spawn into a different repo than the user's current project without an
  explicit path/repo ask.
- Pass an empty `-p` when you have conversation context to hand off.
- Keep working a child's task, or report child residuals as this session's
  unfinished work, unless the user re-assigns it here.
- Clean up worktrees afterward unless asked (`wt remove` is a separate explicit
  action).
