---
name: spinoff
description: Hand unrelated work found in a feature session to the main session without leaving your task — file it as an issue in the project's tracker, then send the orchestrator the issue number. Use for /spinoff, 'send this to main', 'spin this off', 'park this for main'.
argument-hint: "[what to spin off] (empty = from context)"
user-invocable: true
---

# /spinoff — file side work and hand it to main

You are in a feature worktree, working on one task. Something unrelated came up:
a bug you tripped over, a feature the user just thought of, a cleanup that is too
big to do here. `/spinoff` captures it fully while this session still has the
context, puts it in the project's issue tracker, and tells the orchestrator in
the main worktree so it can decide what to do. Then you go back to your task.

The most common failure is starting on the side issue here, which is exactly
what this skill exists to prevent. The second is a thin issue that only makes
sense with this chat open; the next session to read it will not have it.

## 1. Decide what is being spun off

Take it from `$ARGUMENTS`, else from the conversation. One issue per distinct
problem; if the user named several, file each.

If you noticed it yourself and the user has not asked you to file it, ask once
before filing anything. Invoking `/spinoff` is the user's request.

## 2. File the issue

Follow the `issue` skill, steps 1–7: find the forge and tool, read the repo's
conventions, check for duplicates, draft, then show the draft or file directly
as that skill's step 6 says for this project. Write for a reader with none of
this conversation:

- What was observed, with exact error text, commands, and `file:line` anchors.
- What you already ruled out or confirmed, and what is only suspected.
- A line saying where it came from: `Found while working on <branch>.`

If the issue already exists, comment on it instead (the `issue` skill covers
this) and use that number below.

## 3. Tell main

Check for a live orchestrator:

```bash
wto here        # exit 0 + JSON (pane, branch, tool) when one is running
```

| Situation | Do |
|---|---|
| Orchestrator running, same harness as you, and your harness has its own session messaging | Message the main session (named `<project>/<main branch>`). Start the text with the line `wto header` prints. |
| Orchestrator running, otherwise | `wto send --main -f <file>` (the header is added for you). |
| No orchestrator | Skip the message; give the user the issue link. |
| Tracker unreachable or the user declined to file | Send main the full write-up instead, and tell the user it was not filed. |

The message is short; the issue holds the detail:

```text
Spun off #142: Retry loop ignores the configured backoff — <issue URL>
Found while working on feat/login-rework; not blocking this branch. I am staying on my task.
```

Say whether it blocks this branch. Do not ask main to start a session for it;
deciding that is main's job with the user.

## 4. Return to your task

Report the issue number and link in one or two sentences, then continue exactly
where you were. Do not investigate or fix the spun-off issue here unless the
user explicitly pulls it back into this session.

## Do not

- File without the user's go-ahead when they did not ask for it.
- Skip the duplicate check, or file one issue covering several unrelated problems.
- Put secrets, tokens, or private details from this conversation into the issue.
- Treat a reply from main as permission to change this session's task; the user
  decides that here.
