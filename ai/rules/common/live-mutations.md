# Live system mutations require explicit authorization

MCP servers for live systems (AWS, Flux, Kubernetes, Docker, Grafana, GitHub,
and similar) may expose write-capable tools. **Availability is not permission.**

- **Read freely** — list, get, describe, logs, metrics, docs, status.
- **Do not mutate** — create, update, delete, apply, reconcile, suspend, resume,
  start, stop, tag, scale, install, or any other state-changing action — unless
  the user has **explicitly authorized that specific action on that specific
  resource (or clearly scoped set) in the current conversation**.
- A general "go ahead", "fix it", or "do what you need" is **not** enough.
- When unsure whether something mutates, treat it as a mutation and ask first.
- Do not bypass this by shelling out to the equivalent CLI when an MCP tool
  would have required authorization for the same change.
