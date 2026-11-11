---
name: plan-implement-review
description: Work a task in three stages with the planner, implementer and reviewer subagents — a written plan, a build from that plan, and a fresh-eyes review of the diff against it. Use for /plan-implement-review, when a task needs a plan before code, when handing a finished plan off to be built, or before calling a change done or ready.
user-invocable: true
---

# Plan, implement, review

Each stage has its own subagent, and each subagent carries its own model and
effort, so the session never switches models mid-conversation. The session
does the stage that needs a conversation and delegates the rest. A subagent
starts with an empty context and cannot ask the user anything: everything it
needs goes in the plan file and the brief.

The most common failure is a thin handoff: a one-line brief, or a plan that
leaves the real decisions open, so the implementer guesses. The second is
skipping the review because the checks passed. The third is passing a model
when starting one of these subagents; each one's definition already sets it.

## Who does which stage

| Session | Plan | Implement | Review |
|---|---|---|---|
| The user is here | The session, with the user | `implementer` | `reviewer` |
| Unattended (a worktree handoff, an orchestrated session) | `planner`, when the handoff says plan first, the cause is unknown, the work spans several parts of the system, or it is risky; otherwise none | The session | `reviewer` |

A small, fully specified change (a rename, a config value, a known error with
an obvious cause) skips the plan but still gets the review.

Only the session starts subagents. Never ask one stage's subagent to start
another.

## The plan file

Save the plan to `"$(git rev-parse --git-dir)/ai-plan.md"`: it stays out of
the working tree, belongs to this worktree, and goes away with it. Outside a
git repository, use a temp file. Replace it for each new task, and give its
path in every brief.

The plan has these sections; the `planner` returns them in this shape:

| Section | Holds |
|---|---|
| Goal | What done looks like; the acceptance check |
| Findings | What the code does today, with `file:line`; the cause of a bug |
| Decisions | Each choice and why, including what the user chose |
| Steps | Ordered changes, each with the files it touches |
| Checks | Exact commands that prove it works |
| Out of scope | What not to touch |
| Open questions | Decisions only the user can make |

Settle every open question before implementing. With the user here, ask.
Unattended, report them as a blocker instead of guessing.

## Briefs

| Subagent | The brief carries |
|---|---|
| `planner` | The task as described, what is known and ruled out, constraints |
| `implementer` | The plan file path, and review findings when fixing them |
| `reviewer` | The plan file path, and what to review when it is not the uncommitted changes (a commit range) |

Restate any constraint that is in neither the plan nor the project's
instructions.

## The review loop

1. Start the `reviewer` once the implementation passes its checks.
2. Read the cited lines for each finding before acting on it; a reviewer can
   be wrong.
3. Fix the confirmed findings: send them to the `implementer` (continue the
   same one where the harness can resume a subagent, otherwise start a new one
   with the plan path and the findings), or fix them yourself when the session
   implemented.
4. Rerun the checks. Review again only when the fixes changed logic, and stop
   after two review rounds; report what is still open.
5. Commit in logical groups once the review is clean, by the project's commit
   rules.
