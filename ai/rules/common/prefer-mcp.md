# Prefer MCP servers when one fits

MCP servers return live, authoritative data. Prefer them over CLI suggestions,
web scraping by hand, or training-data recall whenever one matches the task.

## Pick the right server (most specific first)

**Domain / live systems** (use these before general docs or web tools):

| Need | Server |
|---|---|
| Kubernetes cluster state (pods, logs, events) | `kubernetes` |
| Flux GitOps state and reconcile ops | `flux` |
| AWS account state *and* AWS docs/skills | `aws` |
| Terraform/OpenTofu provider/module registry docs | `terraform` |
| Grafana dashboards / observability | `grafana` |
| Docker engine / containers | `docker` |
| GitHub PRs, issues, repos | `github` |
| Browser automation / UI screenshots | `playwright` |

**General knowledge** (only when no domain server covers it):

| Need | Server |
|---|---|
| Library/SDK/framework API docs and examples (npm, PyPI, Go modules, etc.) | `context7` |
| Open-web search, scrape a known URL, multi-page research, changelogs, CVEs, blogs | `firecrawl` |

## Rules of thumb

1. **Never invent package APIs from memory** when Context7 (or a domain docs server) can answer. Hallucinated method names are the common failure mode.
2. **Context7 is for packages; Firecrawl is for the open web.** Do not use Firecrawl as a first-line substitute for library docs, and do not use Context7 for general news or arbitrary URLs.
3. **If Context7 misses a library** (empty/wrong index), fall back to Firecrawl against the *official* docs URL — not random blog posts.
4. **AWS docs** go through the `aws` server's documentation tools when available, not Context7 or Firecrawl.
5. **Terraform provider/module schemas** go through `terraform`, not Context7 or Firecrawl.

## Live systems: read free, mutate only when authorized

Domain servers often expose write tools. Prefer them for **reads**; for
**mutations**, follow `live-mutations.md` — explicit per-action authorization
in the current conversation. Availability is not permission.

## Disabled servers

Only `context7` and `firecrawl` are enabled by default. Domain servers (`kubernetes`, `flux`, `aws`, `terraform`, etc.) often ship disabled. If a needed server is configured but disabled, **ask the user to enable it** before falling back to Bash/CLI or guessing.
