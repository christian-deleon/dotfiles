---
name: backlog
description: Pick the next batch of work from the project's issue tracker for the orchestrator — rank open issues, skip what sessions already cover, and propose a capped batch that can run side by side. Use inside /orchestrate for /backlog, 'what should we work on next', 'pick issues to work on'.
argument-hint: "[label, milestone, or search terms]"
user-invocable: true
---

# /backlog — choose what runs next from the tracker

A project can have a hundred open issues and room for three sessions. `/backlog`
turns the tracker into a short, defensible proposal: the few issues worth
starting now, which can safely run at the same time, and what waits. It feeds the
orchestrator's dispatch step; it starts nothing on its own and writes nothing to
the tracker.

The most common failure is proposing as many sessions as there are interesting
issues. The cap is the cap, and two sessions in the same area or needing the
same shared resource are worse than one. The second is reading every issue in
full; read titles and labels first, and only the shortlist in depth.

Run it in the orchestrator session (`wto here` shows this pane). Elsewhere it
can still produce the proposal, but only the orchestrator dispatches.

## 1. Find the tracker

Use the `issue` skill's steps 1–2 to find the forge and the tool. The profile's
`Issues:` line says where issues live when that differs from the git remote, and
its `priority:` part says what marks priority.

## 2. Cheap pass: open issues, metadata only

| Tool | List |
|---|---|
| `gh` | `gh issue list -R owner/repo --state open --limit 200 --json number,title,labels,milestone,assignees,updatedAt,comments` |
| `tea` | `tea issues list --login <name> --repo owner/repo --state open --limit 200 --output json` |
| `glab` | `glab issue list -R owner/repo --per-page 100 --output json` (open issues by default) |
| `gitea` MCP | the issue list tool, state open |

Narrow with `$ARGUMENTS` (a label, milestone, or search terms) when given.

## 3. Filter and rank

Drop:

- Issues an open session already covers: `wto ls --json` branch names carry
  issue numbers, and `"$(wto dir)/next-up.md"` lists what is queued.
- Issues assigned to someone else, or labeled as blocked, waiting, or needing
  information.

Rank by, in order: the profile's priority signal; priority or severity labels;
bugs over features over chores; a near milestone; recent activity. Keep a
shortlist of about twice the free session slots, at most ten.

Free slots are the profile's session cap (default 5) minus the live non-main
sessions in `wto ls`.

## 4. Read the shortlist in a subagent

Give a subagent the issue numbers and the tool commands, and ask it to read each
issue's body and comments and return, per issue:

- a two-line summary and what "done" looks like;
- the part of the code it names (paths, components), from the issue text only;
- a rough size: small, medium, large;
- dependencies on other issues;
- shared resources from the profile it would need (for example a deploy target);
- questions only the user can answer.

The subagent reads issues, not code. Keep its report in your context; do not
paste issue bodies into chat.

## 5. Build the batch

Fill the free slots from the top of the ranking, skipping an issue when it
touches the same area as one already picked, needs the same shared resource at
the same time, or depends on one not yet done. Issues with open questions go to
the user instead of the batch.

Present:

```text
Proposed now (2 of 3 free slots):
  #212  fix/212-retry-backoff     Retry loop ignores backoff     high-priority bug, small   sonnet medium (cause named in the issue)
  #198  feat/198-export-csv       CSV export for reports         milestone 1.9, medium      opus xhigh (ordinary feature)

Next up: #205 (needs the deploy target #212 also uses), #190 (depends on #198)
Questions: #201 — which of the two proposed APIs do you want?
```

Branch names follow the profile's `Branch naming`, with the issue number. Model
and effort come from the `wtc` skill's table, using the subagent's size and
summary, within the profile's `Models:` line.

## 6. Hand over

On the user's approval, the orchestrator spawns the approved items (its dispatch
step). Write the rest, with the reason each waits, to `"$(wto dir)/next-up.md"`.

Do not label, assign, comment on, or close issues unless the user asks; then
follow the `issue` skill for the write.
