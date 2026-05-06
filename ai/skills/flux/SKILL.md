---
name: flux
description: Modern Flux CD (v2) GitOps authoring for Kubernetes. Activate when working in a directory containing flux/, clusters/, or YAML files referencing toolkit.fluxcd.io APIs (GitRepository, OCIRepository, HelmRepository, HelmRelease, Kustomization), or when the user mentions Flux, GitOps reconciliation, `flux bootstrap`, or the `flux` CLI. Enforces current API versions, the source/reconciler split, a four-layer reconcile chain, and the preferred secrets pattern (1Password Operator + Reflector, not SOPS/ESO).
compatibility: opencode
---

# Flux CD Authoring

Flux v2 only. Flux v1 has been EOL for years — never produce `flux.weave.works`-style manifests, `HelmRelease` v1 syntax, or anything referencing the old `Flux` operator. The everything-is-a-CRD model is the only model.

Before adding new patterns to a Flux repo, **mirror what the existing repo already does** — directory layout, HelmRelease boilerplate, secret strategy. Don't introduce a parallel convention alongside an existing one. The conventions below are the defaults when starting fresh.

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

## Repository structure

Monorepo, four layers, with one base catalog and per-cluster overlay directories. Each cluster gets its own entrypoint and reconciles everything else via Flux Kustomizations chained with `dependsOn`:

```
flux/
├── clusters/<cluster_name>/
│   ├── flux-system/                 # bootstrap-managed, do not edit by hand
│   ├── infrastructure.yaml          # Flux Kustomization → infrastructure/<cluster>
│   ├── dependencies.yaml            # depends on infrastructure
│   └── apps.yaml                    # depends on dependencies
├── infrastructure/                  # controllers, CRDs, cluster-wide concerns (cert-manager, traefik, cnpg operator, 1password connect, alloy)
│   ├── base/<component>/            # HelmRelease + Source + namespace + kustomization.yaml
│   └── <cluster_name>/kustomization.yaml   # overlay listing ../base/* refs
├── dependencies/                    # things infra installs but apps need (DB clusters, certs, secret reflectors, operators)
│   ├── base/<component>/
│   └── <cluster_name>/kustomization.yaml
└── apps/                            # workloads
    ├── base/<app>/
    └── <cluster_name>/kustomization.yaml
```

Reconcile order via `dependsOn`: `infrastructure → dependencies → apps`. Don't put everything under one Flux Kustomization — you lose ordering and a single failed reconcile blocks everything. The four-layer split is deliberate: `dependencies` exists for things that aren't infrastructure controllers but aren't user apps either (a Postgres cluster managed by the cnpg operator, a Redis StatefulSet, cert-manager `Certificate` resources, secret reflectors).

**Multi-tenant variant**: when one repo serves multiple product domains, nest the four layers under each domain:

```
infra/flux/
├── <domain-a>/{clusters,infrastructure,dependencies,apps}/...
├── <domain-b>/{clusters,infrastructure,dependencies,apps}/...
└── <domain-c>/{clusters,infrastructure,dependencies,apps}/...
```

Each domain bootstraps its own clusters and reconciles only its own catalog. Don't cross domain boundaries.

## Per-cluster overlay kustomization.yaml

Each per-cluster overlay is a plain kustomize file that lists the base components for that cluster, with a Flux prune annotation propagated to every child resource:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

commonAnnotations:
  kustomize.toolkit.fluxcd.io/prune: "true"

resources:
  - ../base/cert-manager
  - ../base/cnpg
  - ../base/redis
  - ../base/reflector
```

Prefer this over `postBuild.substitute` for per-cluster variation: vary by **what each per-cluster overlay includes** (and per-cluster overrides via `patches:` when needed). Substitution variables make manifests harder to render and review locally; overlay directories don't.

## Cluster entrypoint files

Plain Flux Kustomizations, chained via `dependsOn`. Default to `dependsOn` alone — don't add `wait: true` unless a downstream layer genuinely needs the upstream resources to be reported healthy (not just applied) before reconciling. `wait: true` plus a slow rollout can deadlock the chain.

```yaml
# clusters/<name>/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 1m0s
  path: ./flux/infrastructure/<cluster>
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
---
# clusters/<name>/dependencies.yaml — same shape, plus:
spec:
  dependsOn:
    - name: infrastructure
---
# clusters/<name>/apps.yaml — same shape, plus:
spec:
  dependsOn:
    - name: dependencies
```

`prune: true` is the right default — without it, removing a manifest from git leaves the resource orphaned in the cluster.

## Source / reconciler split

Sources (`GitRepository`, `OCIRepository`, `HelmRepository`, `Bucket`) only fetch artifacts. Reconcilers (`Kustomization`, `HelmRelease`) consume them. Keep them in separate files; one source can serve many reconcilers.

```yaml
# helmrepository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: jetstack
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
```

`HelmRepository` for traditional HTTP chart repos. **Use `OCIRepository` whenever the chart is hosted in an OCI registry** (the modern default — `ghcr.io`, ECR, Harbor). `OCIRepository` references in `HelmRelease` use `chartRef` instead of `chart.spec.sourceRef`.

```yaml
# OCIRepository for a private OCI-hosted Helm chart
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: my-chart
  namespace: flux-system
spec:
  interval: 5m
  url: oci://registry.example.com/path/to/chart
  ref:
    semver: "*"             # or pin: tag: "1.2.3"
  secretRef:
    name: registry-creds    # private registry pull
  layerSelector:
    mediaType: "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
    operation: copy
```

## HelmRelease v2 — standard shape

Always include `releaseName`, both remediation blocks, `driftDetection`, and `reconcileStrategy: ChartVersion` for HelmRepository charts:

```yaml
# HelmRepository (HTTP) — most common
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  releaseName: cert-manager
  interval: 24h                  # stable infra: 24h. Iterated apps: 5m.
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  chart:
    spec:
      chart: cert-manager
      version: "1.14.4"          # pin exactly, or use ">=X.Y.Z" for floor-only
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: jetstack
        namespace: flux-system
  driftDetection:
    mode: enabled
  values:
    installCRDs: true
```

```yaml
# OCIRepository — chartRef instead of chart.spec
spec:
  chartRef:
    kind: OCIRepository
    name: my-chart
    namespace: flux-system
```

Pin chart versions explicitly. `version: "*"` is acceptable when paired with an `OCIRepository` whose `ref.semver` already constrains the range, but in HelmRepository contexts pin exactly. `>= X.Y.Z` floor constraints are fine for things you genuinely want to roll forward.

`targetNamespace` and `releaseName` are independent of `metadata.namespace`. If you want the release to land in a different namespace than the HelmRelease object, set `spec.targetNamespace` and `spec.releaseName` explicitly.

## Secrets — 1Password Operator + Reflector

The default secrets pattern is 1Password Connect + Operator, **not** SOPS, ESO, or Sealed Secrets:

1. **`infrastructure/base/1password/`** installs the 1Password Connect Helm chart with the operator enabled. The chart pulls credentials from a pre-provisioned `op-credentials` Secret and a token Secret in the `1password` namespace.
2. **App manifests reference 1Password items via `OnePasswordItem` CRDs**. The operator materializes a regular `Secret` with the same name in the same namespace:
   ```yaml
   apiVersion: onepassword.com/v1
   kind: OnePasswordItem
   metadata:
     name: app-db-credentials
     namespace: app
   spec:
     itemPath: "vaults/<vault-uuid>/items/<item-uuid>"
   ```
3. **Cross-namespace replication uses `emberstack/reflector`**. Install via `dependencies/base/reflector/`. Annotate a source Secret to allow reflection, and a target namespace's annotation pulls it in. Common case: the cnpg operator needs DB credentials in the `postgres` namespace, but the consuming app needs them in its own namespace too.

Don't introduce SOPS or ESO into a repo that already uses this pattern. If a new project genuinely needs SOPS, the Flux Kustomization gets a `decryption: { provider: sops, secretRef: { name: sops-age } }` block — but make that an explicit decision, not an accidental drift.

Never commit plaintext `Secret` manifests. The only `Secret`-like things in git are `OnePasswordItem` resources and Reflector reflections.

## Reconcile intervals — pick the right cadence

Don't put `interval: 30s` everywhere — you'll rate-limit yourself off public registries and burn API server requests.

| Resource | Interval |
|---|---|
| Cluster Flux `Kustomization` (infra/deps/apps entrypoints) | `1m` |
| `HelmRepository` (HTTP chart index) | `1h` |
| `OCIRepository` | `5m` |
| `HelmRelease` (stable infra: cert-manager, 1password, reflector) | `24h` |
| `HelmRelease` (iterated apps) | `5m` |
| `ImageRepository` | `1m`–`5m` |

## Bootstrap

`flux bootstrap` is the only supported install path. It commits the controller manifests + a `flux-system` Kustomization into `clusters/<name>/flux-system/` in your repo, and Flux reconciles itself from there.

- Don't edit `flux-system/gotk-components.yaml` or `gotk-sync.yaml` by hand. Re-run `flux bootstrap` to upgrade or change settings.
- Bootstrap once per cluster; `--path=./flux/clusters/<cluster_name>` keeps clusters isolated.
- Use `--components-extra=image-reflector-controller,image-update-controller` if you want image automation.

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

## Image automation (optional)

If using image-update-automation, three CRDs work together: `ImageRepository` (scans tags) → `ImagePolicy` (selects one per a strategy: semver, regex, alphabetical) → `ImageUpdateAutomation` (commits the new tag back to git). Annotate the YAML field to update with `# {"$imagepolicy": "ns/policy"}`. The bot writes commits; Flux reconciles them like any other change. If the repo already uses Renovate for version bumps, don't duplicate that with image-automation — pick one.

## Validate before committing

```sh
# Render and validate Kustomize bases
kubectl kustomize ./flux/apps/base/<app> | kubectl apply --dry-run=client -f -

# Validate Flux manifests against the schemas
flux check
flux tree kustomization <name>     # see the resource graph
flux diff kustomization <name> --path ./flux/...  # preview a reconcile vs the cluster
```
