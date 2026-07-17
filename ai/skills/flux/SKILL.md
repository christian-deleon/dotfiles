---
name: flux
description: Flux CD v2 GitOps for Kubernetes. Use when editing YAML under `flux/`/`clusters/` referencing `toolkit.fluxcd.io` APIs (GitRepository, HelmRelease, Kustomization, ResourceSet), or for prompts about Flux, GitOps reconciliation, `flux bootstrap`, 'add a HelmRelease', 'fix the Kustomization', 'reconcile this'. Preferred secrets: 1Password Operator + Reflector.
compatibility: opencode
---
# Flux CD Authoring

Flux v2 only. Flux v1 has been EOL for years — never produce `flux.weave.works`-style manifests, `HelmRelease` v1 syntax, or anything referencing the old `Flux` operator. The everything-is-a-CRD model is the only model.

Before adding new patterns to a Flux repo, **mirror what the existing repo already does** — directory layout, HelmRelease boilerplate, secret strategy. Don't introduce a parallel convention alongside an existing one. The conventions below are the defaults when starting fresh.

## Decision tree

| Need | Read |
|---|---|
| Repo layout, overlays, entrypoint Kustomizations | [layout.md](layout.md) |
| Sources, HelmRelease shapes, intervals | [sources-helm.md](sources-helm.md) |
| Secrets, bootstrap, image automation, validate | [ops.md](ops.md) |


## Current API versions

Always emit GA versions:

| Kind | apiVersion |
|---|---|
| `GitRepository`, `OCIRepository`, `HelmRepository`, `Bucket` | `source.toolkit.fluxcd.io/v1` |
| `Kustomization` (Flux) | `kustomize.toolkit.fluxcd.io/v1` |
| `HelmRelease` | `helm.toolkit.fluxcd.io/v2` |
| `Provider`, `Alert`, `Receiver` | `notification.toolkit.fluxcd.io/v1beta3` |
| `ImageRepository`, `ImagePolicy`, `ImageUpdateAutomation` | `image.toolkit.fluxcd.io/v1beta2` |

Never `helm.toolkit.fluxcd.io/v2beta1` or `v2beta2` — both deprecated. Never `v1alpha1` for Source/Kustomize APIs.

**Two different `Kustomization` kinds exist** and AI agents constantly conflate them:
- `kustomize.toolkit.fluxcd.io/v1` — Flux's reconciler resource (lives in the cluster, points at a path).
- `kustomize.config.k8s.io/v1beta1` — the `kustomization.yaml` file inside the path that lists `resources:` for `kubectl kustomize` to render.

A typical app has both: a Flux Kustomization in `clusters/<env>/` that points at a directory containing a `kustomization.yaml` (the kustomize one).

## Don't / Do

| Don't | Do |
|---|---|
| `helm.toolkit.fluxcd.io/v2beta1` or `v2beta2` | `helm.toolkit.fluxcd.io/v2` |
| `HelmRepository` pointing at an OCI URL | `OCIRepository` + `chartRef` in HelmRelease |
| Mix `kustomize.toolkit.fluxcd.io` and `kustomize.config.k8s.io` in your head | Different — Flux Kustomization reconciles, kustomize.yaml renders |
| Unpinned `version:` in HelmRelease w/ HelmRepository | Exact pin, or `>= X.Y.Z` floor with remediation |
| `prune: false` (or omitted) on Flux Kustomizations | `prune: true` unless you have a specific reason |
| Apply resources via `flux create` at runtime | Commit YAML to git; `flux create` is for one-off experiments |
| Plaintext `Secret` in git | `OnePasswordItem` + Reflector for cross-ns replication |
| Introduce a second secrets pattern alongside an existing one | Match the repo's existing convention (1Password Operator by default) |
| One Flux Kustomization for the whole cluster | Four-layer chain: infrastructure → dependencies → apps |
| `postBuild.substitute` to vary config per cluster | Per-cluster overlay directory listing different bases / patches |
| `interval: 30s` on `HelmRepository` | `1h` — chart indexes don't change minute-to-minute |
| Hand-edit `flux-system/gotk-*.yaml` | Re-run `flux bootstrap` |
| Use `flux suspend` / `resume` as a deploy gate | Use git (revert the commit) — suspending hides drift |
