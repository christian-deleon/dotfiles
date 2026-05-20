---
name: kubernetes-mcp
description: Kubernetes cluster API access via the `kubernetes` MCP server. Use whenever a task requires reading live cluster state (pods, deployments, logs, events, configmaps) or kubectl-style answers — 'what pods are running', 'why is this deployment unhealthy', 'show me the logs', 'describe this resource'. Read-only by default.
compatibility: opencode
---

# Kubernetes MCP Usage

All Kubernetes cluster API access goes through the `kubernetes` MCP server (`mcp__kubernetes__*` tools). Do not shell out to `kubectl` via the Bash tool for live cluster queries.

## If the MCP server is not enabled

If `mcp__kubernetes__*` tools are not available, **stop and ask the user to enable the `kubernetes` MCP server** before proceeding. Do not fall back to running `kubectl` via Bash, and do not try to construct API calls another way.

## What the MCP server is for

Cluster state reads — what is running, what its config looks like, what its logs say, what events the API server recorded. Examples:

- `mcp__kubernetes__pods_list_in_namespace`, `mcp__kubernetes__pods_get`, `mcp__kubernetes__pods_log` — pod state and logs
- `mcp__kubernetes__resources_list`, `mcp__kubernetes__resources_get` — any kind (deployments, services, ingresses, CRDs)
- `mcp__kubernetes__events_list` — recent cluster events (the single most useful debugging signal)
- `mcp__kubernetes__nodes_log`, `mcp__kubernetes__nodes_top`, `mcp__kubernetes__nodes_stats_summary` — node-level diagnostics
- `mcp__kubernetes__namespaces_list`, `mcp__kubernetes__configuration_contexts_list`, `mcp__kubernetes__configuration_view` — what cluster and context you're talking to
- `mcp__kubernetes__pods_top` — live CPU / memory usage

When in doubt, check `mcp__kubernetes__events_list` for the namespace first. Most cluster confusion is one events query away from clarity.

## Read-only by default

Only invoke read-only Kubernetes actions (`list`, `get`, `log`, `top`, `view`, `stats_summary`).

Do **not** call any action that creates, modifies, or deletes Kubernetes resources unless the user has **explicitly authorized that specific change in the current conversation**. A general "go ahead" is not enough — confirm the exact action and target resource before mutating.

Specifically, these write-capable tools require explicit per-action authorization:

- `mcp__kubernetes__resources_create_or_update`
- `mcp__kubernetes__resources_delete`
- `mcp__kubernetes__resources_scale`
- `mcp__kubernetes__pods_delete`
- `mcp__kubernetes__pods_exec` (treat as a mutation — exec sessions can do anything)
- `mcp__kubernetes__pods_run`

When in doubt, treat the action as a mutation and ask first.

## Mutations should go through GitOps, not the MCP server

Even when authorized, prefer to **make the change in git and let Flux reconcile it** rather than mutating the cluster directly through the MCP. The cluster is a projection of the git repo; live edits create drift. Use the MCP for diagnostics, GitOps for changes. The only exceptions are throwaway investigation pods and emergency drains/restarts the user has explicitly asked for.

## Confirming which cluster you're on

Before reading anything sensitive, confirm the cluster context. The MCP server reads `KUBECONFIG` from the environment in which it was launched — that may not match the user's current shell.

```
mcp__kubernetes__configuration_view              # current config
mcp__kubernetes__configuration_contexts_list     # all available contexts
```

If the user mentions a specific cluster ("check prod-east", "what's running in dev"), verify the context matches before answering. Don't assume.
