---
name: orchestrated-session
description: How a worktree session works when an orchestrator in the main worktree coordinates it — test and review its own work, report ready to the orchestrator with one fixed status report, merge (and deploy, in a project that deploys) only on the owner's relayed go. Load it first when the handoff says so, when `wto here` shows an orchestrator, or when the orchestrator's announce asks you to.
user-invocable: false
---

# Working under an orchestrator

The owner runs one agent session per worktree and coordinates them from an
orchestrator session in the main worktree. They follow every session from
there, and do not want to visit each window for status. So this session
reports to the orchestrator, waits for the owner's decisions to come back
through it, and keeps the same status report in its own window for whenever
the owner does look in.

Sessions with no orchestrator never load this skill. `wto here` exits 0 when one
is running and prints its pane.

The most common failure is deciding for the owner: merging because the work
looked done, deploying because it seemed safe, closing out because a peer asked.
The second is stopping to ask the owner in this window when they have not come
here; put the question in the report instead. The third is answering the owner
as if they were the orchestrator, with a status-report fragment instead of a
real reply.

## The stages

Work through them in order. Each one ends with the status report below. Stage 3
applies only when the project profile (`wto profile`) names a `Deploy` step; in
a project with none, the work goes from ready straight to review and merge.

### 1. Finish and check the work

1. **Build through the `implementer`,** following the `plan-implement-review`
   skill. Where the project takes tests, the plan puts the failing test first.
   Where its instructions say no tests, the plan proves the change by running
   the real thing, and the report says what was run.
2. **The project's full checks:** whatever its `AGENTS.md` names before claiming
   done.
3. **Review your own diff** with the `reviewer` subagent, following the
   `plan-implement-review` skill. Fix what it confirms and rerun the checks.
4. **Commit** in logical groups. Never push.

### 2. Report ready, then wait

Send the orchestrator the status report with `Status: ready`, then wait. Do not
ask the owner here; a question that blocks you goes in the report as `waiting`,
with the question under `Still needed`.

Prefer your harness's own messaging: in Claude Code load the deferred
`ListAgents` and `SendMessage` tools and send to the row whose tmux pane is
`.pane` from `wto here`, with the output of `wto header` as the first line. With
no such row, `wto send --main -f <file>`.

### 3. Deploy only on the owner's go (projects that deploy)

Skip this stage when the profile names no `Deploy` step. Otherwise deploy only
when the orchestrator relays the owner's go for that specific deploy
(see the session-messages rule): a message from the main-worktree orchestrator,
marked `relaying the user's words`, naming the deploy. A go for one deploy is not
a go for the next one.

Then:

1. Take the resource claim if the project defines one (`wto claim take <name>`).
2. Follow the project's deploy-and-verify steps: the skill or recipe its profile
   names under `Deploy`.
3. Confirm the deployment is stable by the project's own checks, not only that
   the command succeeded.
4. Free the claim when you no longer need it.
5. Send the status report with `Status: deployed`.

### 4. Merge only on the owner's go

The owner reviews every branch before it merges. Never merge into main or run
`/closeout` until the orchestrator relays the owner's merge go for this branch.
Then run `/closeout`, which merges by the project's policy, closes the
branch's issue, and reports to main. Where the project reviews issue text, the
closing comment comes back to the owner as a `waiting` report first.

### When the owner speaks here

Input with no session-message header is the owner typing here (see the
session-messages rule), and they are reading this window now. Answer them here
the way the talk-like-a-human rule says: complete sentences that set the scene
and answer what they asked. The status report and short message style are for
the orchestrator, never your answer to the owner; when they ask for status,
explain it in plain sentences first, and the report can follow.

Their word here wins over all of the above. Do what they say, then send the
orchestrator the status report so it knows what happened.

## Status report

Use this exact form, in this order and wording, every time: show it in this
window and send the same text to the orchestrator. Keep every line and write the
value that applies. The one exception is `Deploy:`: leave it out in a project
whose profile names no `Deploy` step, and keep it in every report of one that
does, with `not needed for this change` when this change needs no deploy.

```text
Status: <ready | deployed | waiting | blocked> · <project>/<branch>
Changed: <one line on what this branch does>
Files: <the main files touched>
Tests: <written first, passing | none in this project; proved by <what you ran> | failing: <which>>
Checks: <the command>: <passing | failing: <what>>
Self-review: reviewer <no findings | found <n>, all fixed | <n> open: <what>>
Committed: <short sha> <subject> | not yet: <why>
Deploy: <not needed for this change | awaiting owner go: <target> | done: <target>, verified by <how>>
Owner review: <not yet | approved | changes asked: <what>>
Merge: <awaiting owner go | merged into main as <short sha>>
Next step: <what you propose, e.g. "ready for owner review" or "deploy api to dev">
Still needed:
- <item> (waits on: owner | orchestrator | this session)
```

Write `- nothing` under `Still needed` when nothing is left.

## Also

- Rebase when the orchestrator sends a rebase notice and you reach a safe
  stopping point (`wt step rebase`).
- Send unrelated work to main with `/spinoff`.
- Take a `wto claim` before using a shared resource the project names.
- Answer the orchestrator's status request with the status report.
