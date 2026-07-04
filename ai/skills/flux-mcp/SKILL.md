---
name: flux-mcp
description: Flux GitOps cluster access via the `flux` MCP server (flux-operator-mcp). Use whenever a task needs live Flux/GitOps state or operations — 'why is this Kustomization failing', 'reconcile the HelmRelease', 'what version of Flux is running', 'compare this app across clusters', 'suspend reconciliation'. Reads freely; mutations require explicit per-action authorization.
compatibility: opencode
---

# Flux MCP Usage

All Flux and GitOps cluster interaction goes through the `flux` MCP server (`mcp__flux__*` tools), backed by `flux-operator-mcp`. Prefer it over shelling out to `flux` or `kubectl` via Bash for live cluster queries — the MCP tools are purpose-built for Flux resources and return status, events, and inventory together.

This skill governs the **MCP server**. For authoring Flux manifests (HelmRelease, Kustomization, GitRepository, ResourceSet) in git, use the [[flux]] skill. For general (non-Flux) cluster reads, use [[kubernetes-mcp]].

## If the MCP server is not enabled

If `mcp__flux__*` tools are not available, **stop and ask the user to enable the `flux` MCP server** before proceeding. Do not fall back to running `flux`/`kubectl` via Bash. It ships disabled by default (like `kubernetes` and `grafana`); the user enables it per session. The binary is `flux-operator-mcp` — if the server fails to start, the binary may not be installed (`dot install flux-operator-mcp`).

## The tools

**Read-only (use freely):**

- `mcp__flux__get_flux_instance` — Flux Operator install status, version, and settings. Call this first when asked about Flux itself, and after any context switch. **Only works on flux-operator-managed clusters** (it looks up the `FluxInstance` CR). Most clusters here are installed via `flux bootstrap`, where it returns `No Flux instance found` — that means "not operator-managed", not "Flux is broken". Fall back to `get_kubernetes_resources` on the `flux-system` Kustomizations and controller Deployments.
- `mcp__flux__get_kubernetes_resources` — any Flux or Kubernetes resource with its status, events, and inventory. The workhorse.
- `mcp__flux__get_kubernetes_logs` — pod logs for troubleshooting.
- `mcp__flux__get_kubernetes_metrics` — CPU/memory for pods.
- `mcp__flux__get_kubernetes_api_versions` — resolve the correct `apiVersion` for a kind. **Never assume an apiVersion — call this.**
- `mcp__flux__get_kubeconfig_contexts` — list available cluster contexts.
- `mcp__flux__search_flux_docs` — current Flux CRD/docs reference (use `format: complete` for full API docs).

**Mutating (require explicit per-action authorization):**

- `mcp__flux__set_kubeconfig_context` — switch the active cluster.
- `mcp__flux__reconcile_flux_source`, `..._kustomization`, `..._helmrelease`, `..._resourceset` — force reconciliation.
- `mcp__flux__suspend_flux_reconciliation`, `mcp__flux__resume_flux_reconciliation` — pause/resume a resource.
- `mcp__flux__apply_kubernetes_manifest` — server-side apply.
- `mcp__flux__delete_kubernetes_resource` — remove a resource.
- `mcp__flux__install_flux_instance` — install Flux Operator / a Flux instance.

## Mutation posture

This server runs with `--read-only=false`, so the mutating tools are available — but availability is not permission. Do **not** call any mutating tool unless the user has **explicitly authorized that specific action on that specific resource in the current conversation**. A general "go ahead" is not enough. Reconciling, suspending, resuming, and switching context all count as mutations. When in doubt, treat it as a mutation and ask.

`set_kubeconfig_context` deserves special care: switching clusters silently changes the blast radius of every subsequent call. Confirm the target context, then call `get_flux_instance` to verify where you landed before doing anything else.

## GitOps-first: prefer git over direct apply

The cluster is a projection of the git repo. For durable changes, **make the change in git and reconcile**, rather than `apply_kubernetes_manifest` / `delete_kubernetes_resource` directly — live edits create drift that Flux will fight or revert.

- `reconcile_*`, `suspend`, `resume` are legitimate operational actions (still authorize each one) — they don't create drift, they drive the existing desired state.
- `apply_kubernetes_manifest` / `delete_kubernetes_resource` on Flux-managed resources should be a last resort (break-glass, throwaway debug objects). If a Flux-managed resource needs to change, change it in git. Say so instead of applying.

## Multi-cluster handling

1. `get_kubeconfig_contexts` to see what's available.
2. Confirm with the user, then `set_kubeconfig_context` to switch.
3. `get_flux_instance` to confirm the landing cluster and its Flux version/settings (on bootstrap-installed clusters, verify via the `flux-system` Kustomization instead).
4. Then proceed.

When comparing a resource across clusters, focus on `spec` (desired state); pull in `status` and `events` to explain drift, and resolve any `valuesFrom` / `substituteFrom` ConfigMaps and Secrets referenced by the spec.

## Troubleshooting workflow

For a failing Kustomization or HelmRelease:

1. `get_flux_instance` — is the controller healthy at all? (On bootstrap-installed clusters this errors; check the `flux-system` Kustomization and controller Deployments via `get_kubernetes_resources` instead.)
2. `get_kubernetes_resources` on the failing object — read `status.conditions`, events, and inventory.
3. Trace its source (GitRepository / OCIRepository / HelmRepository) — is it ready and at the expected revision?
4. Walk the managed/inventory resources for the actual broken object.
5. `get_kubernetes_logs` on the relevant controller or workload pods (identify Deployment → matchLabels → pods → logs).
6. `search_flux_docs` for the CRD when the failure mode is unclear.

Produce a root-cause summary when you find the issue; a short status summary (managed resources + image versions) when everything is healthy.
