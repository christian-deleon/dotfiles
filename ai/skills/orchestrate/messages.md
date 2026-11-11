# Orchestrator messages

Every message starts with the header line from `wto header` (`wto send` adds it).
Keep messages short and say plainly what you expect: a reply, an action, or
nothing. Fill the `<…>` parts; drop lines that do not apply.

## Announce

```text
An orchestrator session is now running in the main worktree (<project>/main).
You do not need to change anything. It will send notices here: rebase notices when main moves, pause and resume requests, status requests.
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
Status check from the user. Reply in two or three lines: what you are working on, how far along, and anything blocking you or waiting on the user. Then carry on.
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
