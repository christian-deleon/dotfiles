---
name: wtc
description: User-only /wtc — spawn sibling tmux+worktree agent(s) via shell wtc. Pass a message and/or spawn one worktree per listed item. User triggers only; agents may suggest /wtc lines but never auto-run.
compatibility: opencode
argument-hint: "[branch] [message…] | each: … | (empty = from context)"
disable-model-invocation: true
user-invocable: true
---

# /wtc — spawn a parallel fix agent

`/wtc` is the **user-gated** way to hand a bug or task to a fresh agent in a new worktree + tmux window. It wraps the shell function `wtc` from `functions.d/worktrunk.sh`: create (or switch to) a worktree, open a `tav` layout, launch `$AI_TOOL` with an initial prompt. Agent invocations always pass `-n`/`--no-switch` so the new window is created **without** stealing focus from the user's current window.

**Two ways this gets used:**

1. **You run `/wtc` yourself** (or say "wtc that" / "spawn a fix agent" / "one worktree for each") — this skill runs and executes.
2. **An agent finds side work** while on another task — it may *suggest* ready `/wtc …` line(s) (see the always-on rule), but must not execute until you trigger it.

**Authorization for this turn only.** Loading this skill means the user invoked `/wtc` (or explicitly ordered a spawn). That is the only permission you need — do not re-ask. Outside of that, never run `wtc` / `wta` / `wtaa`.

The most common failure mode is treating "we found a bug" as a reason to spawn. It is not — **suggest** `/wtc …` and wait. Another failure mode is a thin prompt ("fix the bug") that leaves the child agent with no context — always pack the handoff into `-p`.

## Arguments — how to pass a message

`$ARGUMENTS` is freeform text after `/wtc`. That text **is** the message seed (plus optional branch). There is no separate flag in the slash command — the shell form uses `-p` under the hood; you build that from args + conversation.

| What you type | What happens |
|---|---|
| `/wtc fix/session-null Null deref at auth/session.go:142 after idle` | Branch = `fix/session-null`. Message seed = everything after the branch. Expanded with conversation context into full `-p` handoff. |
| `/wtc Null deref at auth/session.go:142 after idle` | No branch token → invent `fix/<kebab-slug>` from the message. Rest is the seed. |
| `/wtc` | Empty args → derive branch + full prompt from the **current** problem in this conversation. |
| `/wtc each of the four we found` / `/wtc one for each` / `/wtc` after you listed N issues and said spawn all | **Multi-spawn** — one worktree + agent per item (see below). |
| `/wtc` + a numbered/bulleted list of tasks in `$ARGUMENTS` | Multi-spawn — one per list item. |

**Branch token rule:** first token is a branch only if it looks like one (`type/slug`, or contains `/`). Otherwise the whole string is message seed.

Branch names: short, descriptive (`fix/auth-null-session`, not `fix/thing`). Window name = branch with `/` → `-`.

Optional base branch is rare; only pass shell `wtc`'s second positional base if the user named one explicitly (e.g. `/wtc hotfix/login production …` for a single spawn).

### Multi-spawn (N worktrees)

When the user wants **one agent per issue** — e.g. four discoveries, "create a worktree for each", "spawn all of these", or a multi-item list in `$ARGUMENTS`:

1. Build an ordered list of tasks from `$ARGUMENTS` **and/or** the conversation (what you already suggested, what they just listed).
2. For **each** task, invent a distinct branch (`fix/…` / `feat/…`) and a full self-contained `-p` prompt (same template as single spawn). Do not put all four bugs into one prompt.
3. Run `wtc` **once per task**, sequentially (each call switches the tmux client; the last window stays focused — fine).
4. Report a compact table: branch → window → one-line task.

If the list is ambiguous (can't tell whether two bullets are one task or two), ask once; otherwise act.

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

Sources, in order: `$ARGUMENTS` message seed → recent conversation findings for that item. Do not invent file paths or error text you have not seen — mark unknowns ("suspected — not confirmed") rather than guessing.

### 2. Preconditions

- Cwd must be inside the target git repo (project is resolved from cwd).
- `$AI_TOOL` / `$AI_TOOL_RESUME` must be set (else `wtc` errors — tell the user to run `dot ai-tool`).
- Shell agents often lack interactive functions — source once before the first call:

```bash
source "$HOME/.dotfiles/functions.d/worktrunk.sh"
```

### 3. Run `wtc` (once, or once per task)

Do not dry-run. Do not re-confirm after the user already ran `/wtc`.

**Always pass `-n` / `--no-switch`.** This skill spawns siblings in the background — the user's current window must keep focus. Interactive shell `wtc` (no flag) still jumps by default; agent use must not.

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
- `wtc` creates a real worktree + branch and a new tmux window; with `-n` it does **not** switch the client to that window.

### 4. Report back

Briefly list each spawn:

- Branch and worktree path
- Tmux `session:window` (created; focus stayed put)
- One-line task summary (not a full re-dump of `-p`)

Do not keep working a child's task here unless the user asks. Parallel agents own their items. The user can switch to the new window when ready (`wta <branch>`, tmux window picker, etc.).

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

- Run `wtc` / `wta` / `wtaa` just because you noticed side work — **suggest** `/wtc …` line(s) instead; only execute when this skill was invoked or the user explicitly ordered it this turn.
- Cram multiple unrelated bugs into a **single** child prompt when the user asked for one worktree each — split.
- Spawn into a different repo than the user's current project without an explicit path/repo ask.
- Pass an empty `-p` when you have conversation context to hand off.
- Clean up worktrees afterward unless asked (`wt remove` is a separate explicit action).
