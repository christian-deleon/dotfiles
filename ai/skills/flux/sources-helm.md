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
