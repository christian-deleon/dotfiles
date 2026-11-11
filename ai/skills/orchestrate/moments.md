# Orchestration moments

A project tailors orchestration by writing instructions for these moments under
`### Orchestration moments` in its `## Project profile` (see the `onboard`
skill). Project text replaces the default for that moment, or adds to it when it
says so. A moment with no project text uses the default below.

| Moment | When | Default |
|---|---|---|
| Entering the mode | After the inventory, before handling the first request | Nothing extra. |
| Before spawning | Before each `wto new` | Use the profile's branch naming and `Models` line; give the child the `wtc` handoff template. |
| Before a release | Before starting a main-only skill that changes main or a shared environment | Tell the user which live sessions would be affected (behind main, holding claims) and confirm before starting. |
| After main moves | A close-out merged, a release finished, or the user says main moved | Rebase notices to live sessions that are behind (SKILL.md). |
| A side issue arrives | A session sends an issue number or write-up | Tell the user with the link; ask whether to start a session now or add it to next-up. |
| A resource is requested | A session asks you, or the user asks, about a shared resource | Point it at `wto claim take`; never grant by hand. |
| A resource is freed | `wto claim free` printed a grant, or a session reports freeing | Send the your-turn message to the new holder. |

## Profile fields this skill reads

| Field | Used for |
|---|---|
| `Kind` | Whether to show issue drafts (through the `issue` skill) |
| `Merge to main` | What a close-out does (through the `closeout` skill) |
| `Issues`, `priority` | Where `/backlog` looks and what it ranks by |
| `Session cap` | How many feature sessions may run at once |
| `Models` | The default model and effort for spawned sessions, and any limits; without it, the `wtc` skill's table |
| `Shared resources`, `gate` | The names to put in the announce message; `wto claim define` should match |
| `Main-only skills` | Skills to run in a subagent from main, on the user's order |
| `Work-producing skills` | Skills whose output feeds the dispatch step |
| `Branch naming` | Branch names for spawned sessions |
