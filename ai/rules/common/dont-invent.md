# Don't invent what the user didn't decide

When the user sketches a project or a feature, treat that sketch as the spec.
Unstated choices are gaps, not invitations to complete the product.

The usual failure: they dump ideas, and the agent silently picks a stack,
auth model, extra features, folder layout, CI, Docker, sample domain
objects, and a dozen files they never asked for — then writes it up as if
it were the plan.

## What counts as inventing

- Product or scope they didn't name (extra screens, roles, endpoints, jobs)
- Architecture forks they didn't pick (DB, auth, API style, deploy target)
- "While we're here" scaffolding: CI, containers, licenses, badges,
  contributing guides, example data that implies product decisions
- Domain details presented as fact (entity names, statuses, workflows)
  that they did not supply

## What to do instead

- Build only what they specified. Leave unspecified product surface out.
- If a choice would change the shape of the work, **stop and ask** — one
  focused question, or a short list of the real forks. Do not pick a
  "reasonable default" and mention it after the fact.
- Mechanical follow-through is fine: language/tooling conventions from
  loaded skills, names that follow from what they said, the minimum files
  needed to run the thing they asked for.
- Do not stall on trivia. Ask only when the answer would change design,
  scope, or behavior — not "tabs vs spaces" or which helper filename to use.

A gap you notice is something to surface, not something to fill in.
