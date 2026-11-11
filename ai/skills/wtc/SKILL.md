---
name: wtc
description: Spawn sibling tmux+worktree agent(s) with `wto new` when the user explicitly approves (slash /wtc, "wtc that", "spawn a fix agent", "one for each", …). When this skill runs, spawn yourself — never tell the user a /wtc or shell command to re-run. Builds a full handoff and picks the job (model and effort). Without approval, only suggest /wtc lines.
argument-hint: "[branch] [message…] | each: … | (empty = from context)"
user-invocable: true
---

# /wtc — spawn a parallel fix agent

`/wtc` hands a bug or task to a fresh agent in a new worktree + tmux window. You
run `wto new`, the program behind the user's `wtc` shortcut: it creates (or
switches to) a worktree, opens the `tav` layout, and launches `$AI_TOOL` with an
initial prompt. It is on `PATH` in every shell; nothing needs sourcing.

`wto new` leaves the user's focus where it is. Never pass `--switch`; the user's
own `wtc` jumps by default because a person typing it wants that.

**Two ways this gets used:**

1. **User runs `/wtc`** (or says "wtc that" / "spawn a fix agent" / "one worktree
   for each") — this skill is active. **You spawn.** Run `wto new …` via the
   shell tool yourself. That **is** approval for this turn. Do **not** reply with
   a `/wtc …` line, a shell command, or "here's what to run" for the user to
   copy — they already invoked the skill; your job is to execute.
2. **You find side work** while on another task (skill **not** invoked) — only
   *suggest* ready `/wtc …` line(s) (see always-on rule `no-auto-wtc`); do **not**
   execute until they approve.

**Authorization for this turn only.** User slash `/wtc` or an explicit natural-
language spawn order this turn is the only permission you need — do not re-ask.
Outside of that, never run `wto new` / `wto open` (or `wtc` / `wta` / `wtaa`).

The most common failure mode is treating "we found a bug" as a reason to spawn.
It is not — **suggest** `/wtc …` and wait. Another is a thin prompt ("fix the
bug") that leaves the child with no context — always pass a full handoff.
A third is `--switch` (steals focus). A fourth is **keeping ownership
after spawn**: still implementing the child's task, or treating child work as open
on *this* session's checklist when the user asks "is everything resolved?" —
spawn transfers accountability; see **Ownership after spawn**. A fifth is **when
this skill is already running, printing a command for the user instead of
executing** — that is always wrong.
## Arguments — how to pass a message

`$ARGUMENTS` is freeform text after `/wtc`. That text **is** the message seed
(plus optional branch). There is no separate flag in the slash command — you
build the handoff from args + conversation and pass it to `wto new`.

| What you type | What happens |
|---|---|
| `/wtc fix/session-null Null deref at auth/session.go:142 after idle` | Branch = `fix/session-null`. Message seed = everything after the branch. Expanded with conversation context into a full handoff. |
| `/wtc Null deref at auth/session.go:142 after idle` | No branch token → invent `fix/<kebab-slug>` from the message. Rest is the seed. |
| `/wtc` | Empty args → derive branch + full prompt from the **current** problem in this conversation. |
| `/wtc each of the four we found` / `/wtc one for each` / `/wtc` after you listed N issues and said spawn all | **Multi-spawn** — one worktree + agent per item (see below). |
| `/wtc` + a numbered/bulleted list of tasks in `$ARGUMENTS` | Multi-spawn — one per list item. |

**Branch token rule:** first token is a branch only if it looks like one
(`type/slug`, or contains `/`). Otherwise the whole string is message seed.

Branch names: short, descriptive (`fix/auth-null-session`, not `fix/thing`).
Window name = branch with `/` → `-`.

Optional base branch is rare; only pass `wto new`'s second positional base if
the user named one explicitly (e.g. `/wtc hotfix/login production …` for a
single spawn).

### Multi-spawn (N worktrees)

When the user wants **one agent per issue** — e.g. four discoveries, "create a
worktree for each", "spawn all of these", or a multi-item list in `$ARGUMENTS`:

1. Build an ordered list of tasks from `$ARGUMENTS` **and/or** the conversation
   (what you already suggested, what they just listed).
2. For **each** task, invent a distinct branch (`fix/…` / `feat/…`) and a full
   self-contained prompt (same template as single spawn). Do not put all
   four bugs into one prompt.
3. Run `wto new` **once per task**, sequentially. Focus never moves; the user
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
- Merged commits already on the base branch that the child must not redo: <sha and subject>. Do not re-implement that work.

## Do not
- Do not push, merge, or open a merge request unless the owner asks. Commit as
  you go in logical groups.

## Coordination
- If `wto here` succeeds, an orchestrator session runs in the main worktree:
  load the `orchestrated-session` skill first and follow it. It covers reporting
  ready, deploys and merges only on the owner's relayed go, rebase notices,
  /spinoff for unrelated work, and `wto claim` for shared resources.

## How to work
Follow the `plan-implement-review` skill:
- <risky row only> Plan first with the `planner` subagent.
- <other rows> Skip the `planner`; read the code and write a short plan yourself.
- Build through the `implementer` subagent from that plan, not by editing the
  code yourself.
- Before calling it done, have the `reviewer` subagent check the diff.

## Done when
<acceptance check — what "fixed" looks like>
```

Sources, in order: `$ARGUMENTS` message seed → recent conversation findings for
that item. Do not invent file paths or error text you have not seen — mark
unknowns ("suspected — not confirmed") rather than guessing.

### 2. Preconditions

- Cwd must be inside the target git repo (project is resolved from cwd).
- `$AI_TOOL` / `$AI_TOOL_RESUME` must be set, in the environment or in
  `~/.localrc` (else `wto new` errors — tell the user to run `dot ai-tool`).

### 3. Run `wto new` yourself (once, or once per task)

**Execute in the shell tool.** Do not dry-run. Do not re-confirm. Do not paste
the command (or a `/wtc …` re-invoke) into chat for the user to run — you run it.

Write the handoff to a file and pass it with `-f`, so no quoting can break it
(`-p '<text>'` works for a short one). `wto new` reads the file and leaves it.

**Single:**

```bash
handoff=$(mktemp)
cat >"$handoff" <<'EOF'
<full child prompt>
EOF
wto new -j implement -f "$handoff" '<branch>'
rm -f "$handoff"
```

**Multi** — one `wto new` per item, each with its own branch and handoff file:

```bash
wto new -j small -f "$handoff_one" 'fix/slug-one'
wto new -j implement -f "$handoff_two" 'fix/slug-two'
# …
```

**Job.** Pick it from the task as described; do not read code to decide.
`wto new -j <job>` takes the job's model and effort for the harness in
`$AI_TOOL`. A model the user names wins: pass it with `-m` (and `-e`), which
override the job. The project profile's `Models:` line (`wto profile`, when
present) can rule a job out or name a model.

| The task as described | Job | Plan |
|---|---|---|
| Small and fully specified: a known error with an obvious cause, a rename, a config change | `-j small` | The session writes a short one |
| An ordinary bug or feature where "done" is clear | `-j implement` | The session writes a short one |
| Unknown cause, several parts of the system, or risky (migrations, concurrency, security) | `-j implement` | The `planner` first |

OpenCode sessions start on their configured default whatever the job; say so.
Its subagents still run on their own jobs' models. `wto new` saves the choice
for the worktree, so a reopened session keeps it.

Notes:

- A handoff is required whenever there is a task description (almost always).
- `wto new` creates a real worktree + branch and a new tmux window, and does
  **not** switch the client to it.

### 4. Report back (after the spawn actually ran)

Only after `wto new` has succeeded (or failed) in the shell, briefly list each spawn:

- Branch and worktree path
- Tmux `session:window` (created; focus stayed put)
- One-line task summary (not a full re-dump of `-p`)
- The job, with a few words on why

Then stop. Do not end with "run this" / "try `/wtc …`" / a copy-paste shell
block — the work is done. The user switches when ready (`wta <branch>`, tmux
window picker, etc.).
## Ownership after spawn

**Once `wto new` successfully creates a worktree + agent for a task, that task is no
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

An orchestrator session (`/orchestrate`) is the standing exception: it keeps a
roster of the sessions it started and sends them notices, but it still never
does, re-debugs, or re-verifies their work.

Reopening a dormant worktree's window is `wto open <existing-branch>` (it continues
that session's conversation); it needs the same approval as a new spawn.

Spawning is a clean cut: the full handoff goes out; accountability does not stay
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

**Agent suggestion style** — only when this skill is **not** active (side work;
do not execute until the user triggers):
```text
Want parallel agents? For example:
/wtc fix/session-null Null deref auth/session.go:142 after idle
/wtc fix/retry-race flaky -race in pkg/api/retry_test.go
```
Or one multi-trigger:
```text
/wtc one for each of the four above
```
When the user *does* trigger (`/wtc`, "wtc that", …), switch to **execute** mode
above — never answer an active `/wtc` with another suggestion block.

## Do not

- Run `wto new` / `wto open` (or `wtc` / `wta` / `wtaa`) just because you noticed side work — **suggest**
  `/wtc …` line(s) instead; only execute when this skill was invoked or the user
  explicitly ordered a spawn this turn.
- When this skill **is** active: tell the user to run `/wtc …` again, paste a
  shell command for them to copy, or dry-run with "here's the command" instead
  of calling the shell tool yourself.
- Pass `--switch` from this skill — that steals the user's focus.
- Cram multiple unrelated bugs into a **single** child prompt when the user
  asked for one worktree each — split.
- Spawn into a different repo than the user's current project without an
  explicit path/repo ask.
- Spawn without a handoff when you have conversation context to hand off.
- Keep working a child's task, or report child residuals as this session's
  unfinished work, unless the user re-assigns it here.
- Clean up worktrees afterward unless asked (`wt remove` is a separate explicit
  action).
