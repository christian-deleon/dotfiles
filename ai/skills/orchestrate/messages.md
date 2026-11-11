# Orchestrator messages

Every message starts with the header line from `wto header` (`wto send` adds it).
Keep messages short and say plainly what you expect: a reply, an action, or
nothing. Fill the `<…>` parts; drop lines that do not apply.

## Announce

```text
An orchestrator session is now running in the main worktree (<project>/main).
You do not need to change anything. It will send notices here: rebase notices when main moves, pause and resume requests, status requests.
Load the `orchestrated-session` skill now and follow it: report to me with its status report when your work is ready, and deploy or merge only on the user's go relayed by me.
If you find unrelated work, hand it over with /spinoff. Before using a shared resource (<names from the profile, or "none defined">), take it with `wto claim take <name>` and free it when done.
The user can still work with you directly; their instructions here come first. No reply needed.
```

## Rebase notice

```text
main moved: <one line on what landed, e.g. "v1.8.0 released" or "feat/login-rework merged">.
New on main:
<git log --oneline old..main, at most 10 lines>
You are <n> commits behind. Forecast: <"rebases cleanly" | "conflicts in: <files>">.
Rebase with `wt step rebase` when you reach a safe stopping point, or later if you are mid-change. If a conflict is not obviously yours to resolve, stop and ask the user. No reply needed.
```

## Pause for a shutdown

```text
The user is shutting the machine down soon. At the next safe stopping point:
1. Commit finished work (stash only if it is not commit-worthy).
2. Write a resume note to <state dir>/resume/<your branch, with every / as ->.md (for example resume/fix-login.md for fix/login): what you were doing, the next step, anything you were waiting on.
3. Free any claims you will not need first thing tomorrow (`wto claim free <name>`).
4. Reply "parked" with one line on where you stopped, then wait.
```

## Resume

```text
Good morning: the user is resuming. Read your resume note at <state dir>/resume/<branch with / as ->.md, check `git status`, and continue where you stopped. If main moved overnight, a rebase notice follows. Reply only if something is blocking you.
```

## Status request

```text
Status check from the user. Reply with your status report (the `orchestrated-session` skill), then carry on.
```

## Status report (from a session)

Sessions send this in `ready`, `deployed`, `waiting`, and `blocked` reports and in
answer to a status request. The `orchestrated-session` skill owns the format;
this copy is for recognizing it.

```text
Status: <ready | deployed | waiting | blocked> · <project>/<branch>
Changed: <one line on what this branch does>
Files: <the main files touched>
1. Tests: <written first, passing | none in this project; proved by <what you ran> | failing: <which>>
2. Checks: <the command>: <passing | failing: <what>>
3. Self-review: /code-review <no findings | found <n>, all fixed | <n> open: <what>>
4. Committed: <short sha> <subject> | not yet: <why>
5. Deploy: <not needed | awaiting owner go: <target> | done: <target>, verified by <how>>
6. Owner review: <not yet | approved | changes asked: <what>>
7. Merge: <awaiting owner go | merged into main as <short sha>>
Next step: <what the session proposes>
Still needed:
- <item> (waits on: owner | orchestrator | this session)
```

## The user's go (relayed)

Send with `--relay`; the body is the user's words as they said them. Name the
one action, for example:

```text
Deploy api to dev now.
```

```text
Approved; merge it.
```

## Your turn on a resource

```text
<resource> is yours now: it was handed over when <previous holder> freed it. Run `wto claim check <resource>` to confirm (it acknowledges the grant), use it, and free it with `wto claim free <resource>` as soon as you are done.
```

## Yield request

```text
The user asks whether you can free <resource> for <branch>, which is waiting on it. If you are mid-use, finish safely first. Free it with `wto claim free <resource>` and reply "freed", or reply with when you expect to be done.
```

## Close-out finished

Sent to the user, not a session:

```text
Closed <branch>: its window and worktree are gone, and main is at <short sha>. <n> sessions got a rebase notice.
```
