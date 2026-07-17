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
