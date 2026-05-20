# Using Helm — install, upgrade, diff, rollback, OCI

Helm is two distinct interfaces stuck behind the same binary: a **rendering interface** (`helm template`, `helm lint`) that produces YAML without touching a cluster, and a **release-management interface** (`helm install/upgrade/rollback/uninstall`) that talks to the API server and tracks each release as a versioned object in cluster state. Most user-facing failures are in the second category — missed flags, wrong release names, deploys without preview. The cheat sheets below cover the day-to-day commands and the flags that matter.

In this user's stack, **most charts get applied via Flux's `HelmRelease`, not direct `helm` commands** — see the `flux` skill for the GitOps integration. Direct `helm` commands are still in scope for: local dev / smoke testing, ephemeral CI environments, lab clusters, bootstrapping (e.g. installing Flux itself), and debugging by reproducing what Flux would do.

## Quick command reference

```bash
# Install (first time)
helm install <release> <chart> -n <ns> --create-namespace \
  -f values.yaml -f values-prod.yaml \
  --atomic --wait --timeout 5m

# Upgrade (subsequent)
helm upgrade <release> <chart> -n <ns> \
  -f values.yaml -f values-prod.yaml \
  --atomic --wait --timeout 5m --reset-then-reuse-values

# Combined install-or-upgrade — most common in CI
helm upgrade --install <release> <chart> -n <ns> --create-namespace \
  -f values.yaml -f values-prod.yaml \
  --atomic --wait --timeout 5m

# Preview an upgrade (helm-diff plugin)
helm diff upgrade <release> <chart> -n <ns> -f values.yaml -f values-prod.yaml

# Render manifests offline (no cluster needed)
helm template <release> <chart> -n <ns> -f values.yaml > rendered.yaml

# Render against the cluster (validates resources exist, CRDs are present)
helm template <release> <chart> -n <ns> -f values.yaml --validate

# Rollback to revision N (helm history shows revisions)
helm rollback <release> <N> -n <ns> --wait --timeout 5m

# Uninstall (deletes resources; --keep-history retains revision metadata)
helm uninstall <release> -n <ns>

# Status / history / values / manifest
helm status <release> -n <ns>
helm history <release> -n <ns>
helm get values <release> -n <ns>                    # rendered values
helm get values <release> -n <ns> --all              # incl. computed defaults
helm get manifest <release> -n <ns>                  # rendered manifests
helm get notes <release> -n <ns>                     # NOTES.txt output
helm get hooks <release> -n <ns>                     # hook manifests

# Inspect a chart without installing
helm show chart <chart>                              # Chart.yaml
helm show values <chart>                             # values.yaml
helm show readme <chart>                             # README.md
helm show all <chart>                                # all of the above
helm pull <chart> --untar                            # download + extract
```

## Critical flags — what each one does and when to use it

| Flag | What it does | When |
|---|---|---|
| `--atomic` | On failure, roll back to the prior revision automatically | **Always**, for any install/upgrade. Failed releases leave broken state otherwise |
| `--wait` | Block until all rendered resources are Ready / Available | Always, in production. Skip only for `helm install --no-hooks` style debugging |
| `--wait-for-jobs` | Also wait for `Job` resources to complete | When the chart includes Jobs that gate readiness (migrations, seeds) — Helm 3.5+ |
| `--timeout 5m` | Max time for `--wait`. Default 5m | Bump for slow clusters / large rolls; don't drop below default |
| `--create-namespace` | Create the namespace if it doesn't exist | First install only. Idempotent — safe to leave on |
| `--install` | When paired with `upgrade`: install if release doesn't exist | The right default for CI / idempotent scripts. Use `helm upgrade --install` everywhere |
| `--reset-then-reuse-values` | New values from flags/files, fall back to existing release values for anything unset | Helm 3.14+. **The right default for upgrade.** Replaces the confusing `--reset-values` / `--reuse-values` pair |
| `--reset-values` | Discard existing release values; use only what's in `-f` / `--set` / chart defaults | When you want a clean reset (e.g. cherry-picking out an old override) |
| `--reuse-values` | Reuse the previous release's values; ignore `-f` / `--set` | Avoid — produces surprising "why didn't my override apply" results |
| `--dry-run=server` | Render + send to API server with `dryRun=All`; validates against CRDs, admission webhooks, defaults | The strongest pre-apply check. Cluster-side equivalent of `helm template --validate` |
| `--dry-run=client` | Render-only, no API call (same as `helm template`) | Quick syntax / schema check |
| `--debug` | Print rendered manifests + extra log lines on failure | When `--wait` times out and you need to see what Helm tried to apply |
| `--description "..."` | Human description stored on the release revision | Useful in CI: `--description "deploy from commit $SHA"` |
| `--set-string foo=3` | Force `foo` to the string `"3"` rather than int `3` | When you need to keep a value-typed-as-string (`appVersion`, port names) |
| `--skip-crds` | Skip the `crds/` install step | When CRDs are managed out-of-band (separate `<name>-crds` chart) |
| `--take-ownership` | Adopt existing resources that match by name | Helm 3.17+. Replaces the painful "delete and reinstall" dance for adoption |
| `--insecure-skip-tls-verify` | Don't verify the chart repo's TLS cert | **Never** in CI / prod. Lab clusters with self-signed certs only |
| `--pass-credentials` | Send Helm credentials with cross-domain redirects | Required for some private registries; otherwise off |

## `helm diff` — preview before every upgrade

The `helm-diff` plugin is mandatory for change review. Install once:

```bash
helm plugin install https://github.com/databus23/helm-diff
```

Use it before every `helm upgrade`:

```bash
helm diff upgrade <release> <chart> -n <ns> \
  -f values.yaml -f values-prod.yaml \
  --three-way-merge \                # diff vs the live cluster (catches manual edits)
  --reset-then-reuse-values \        # match the semantics of the upgrade you'll run
  --context 5 \                      # 5 lines of context around each change
  --show-secrets                     # decode secret data in the diff output
```

Read the output. Things that should make you pause:

- **Selector changes** on Deployments, Jobs, StatefulSets — selectors are immutable; this will fail at apply. Bump the chart major version and reinstall, don't try to upgrade.
- **PVC size changes** — only `ResizableInUseVolumeExpansion` storage classes allow online expansion, and even then it's one-way.
- **Removal of resources** with `prevent_destroy`-equivalent semantics (databases, persistent storage, KMS-equivalent). Confirm before applying.
- **CRD changes in the diff** — Helm won't update CRDs automatically. If you see CRD diffs, you need an out-of-band step.

`--three-way-merge` is important: it compares (desired, current live, last-applied) rather than just (last-Helm-state, new-Helm-state). Without it, manual edits in the cluster look like part of the diff or get silently overwritten.

## OCI registries — the modern distribution path

`helm push`/`pull` against OCI registries (ghcr.io, ECR, GAR, Harbor, Quay) is the default for 2026:

```bash
# Authenticate (registry-specific; some examples)
helm registry login ghcr.io -u <username> --password-stdin <<< "$GITHUB_TOKEN"
helm registry login <account>.dkr.ecr.<region>.amazonaws.com \
  -u AWS --password-stdin <<< "$(aws ecr get-login-password --region <region>)"
helm registry login harbor.example.com -u <user>

# Package + push
helm package ./mychart                            # produces mychart-1.4.2.tgz
helm push mychart-1.4.2.tgz oci://ghcr.io/myorg/charts

# Install from OCI
helm install foo oci://ghcr.io/myorg/charts/mychart --version 1.4.2 -n foo

# Pull / inspect
helm pull oci://ghcr.io/myorg/charts/mychart --version 1.4.2 --untar
helm show values oci://ghcr.io/myorg/charts/mychart --version 1.4.2
```

OCI quirks:

- **The URL shape is `oci://<registry>/<path>/<chart-name>`** — the chart name is the *last* path segment. `oci://ghcr.io/myorg/charts/mychart` pushes a chart named `mychart`. If you push from `helm package mychart`, the resulting OCI artifact is at `…/mychart:1.4.2`.
- **No HTTP repo index.** Search doesn't work the same way. To "search" an OCI repo you list registry contents via the registry's own API.
- **Tag = chart version.** OCI tags are immutable in some registries (ECR mutability setting, ghcr default). Repushing a tag is usually a no-op or rejected.
- **No `helm repo add` for OCI.** You install directly from the URL each time, or via Flux's `OCIRepository`.
- **`helm dep update` works against OCI dependencies** as of Helm 3.7+. The dependency block has `repository: oci://…` and `version: ...`; Helm pulls and verifies digests against `Chart.lock`.

### HTTP repositories (still works, but legacy)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --version 1.14.4 -n cert-manager --create-namespace \
  --set installCRDs=true \
  --atomic --wait
```

HTTP repos are fine for consuming community charts that haven't moved to OCI (jetstack, prometheus-community, bitnami via their HTTP mirror). For *publishing* a new chart in 2026, go OCI.

## `helm template` — render and validate offline

`helm template` is the workhorse for CI validation and "what will this actually apply" reviews:

```bash
# Render with the same values you'd install with
helm template foo ./chart -n foo \
  -f values.yaml -f values-prod.yaml \
  > rendered.yaml

# Render and validate against the cluster (resolves CRDs, defaults from admission)
helm template foo ./chart -n foo --validate \
  -f values.yaml -f values-prod.yaml

# Pipe into offline schema validation (no cluster needed; see testing.md)
helm template foo ./chart -n foo -f values.yaml \
  | kubeconform -strict -summary -kubernetes-version 1.30.0

# Render only specific files (when debugging one resource)
helm template foo ./chart -s templates/deployment.yaml -f values.yaml
```

`helm template` does **not** install anything. The output is a YAML stream you can diff, validate, inspect, or feed into kustomize. It's the right tool for:

- Pre-merge CI checks (render every PR, validate with kubeconform).
- Debugging "what does this template actually emit?".
- Bootstrapping a one-time install where you want to `kubectl apply` and avoid Helm's release tracking (rare — usually a bad idea, but legitimate for installing Flux itself).
- Generating snapshots for `helm-unittest` (which uses `helm template` under the hood).

### `--validate` vs `--dry-run=server`

| Flag | Where it runs | What it catches |
|---|---|---|
| `helm template … --validate` | Templates render locally; Helm sends a server-side validation request | Schema, admission webhooks, defaulting. Doesn't touch the API server state |
| `helm install/upgrade --dry-run=server` | Same as `--validate` but in the install path | Same. Also runs Helm's `pre-install` hook validation |
| `helm template …` (no `--validate`) | Pure local render | YAML syntax + template errors only. Misses CRD references, admission rejections |
| `kubeconform` | Offline, against pre-fetched OpenAPI schemas | Same syntax + schema checks as `--validate`, but no admission webhooks. Fast, runs in CI without a cluster |

Use `kubeconform` for fast feedback in CI; use `--validate` (or `--dry-run=server`) against a real target cluster before the actual apply.

## Rollback

Helm tracks revisions as cluster Secrets (`sh.helm.release.v1.<release>.v<n>`). Roll back to any prior revision:

```bash
helm history <release> -n <ns>
# REVISION  UPDATED                STATUS      CHART        APP VERSION  DESCRIPTION
# 1         Mon Apr 1 10:00 2026   superseded  mychart-1.4  2.18.0       Install complete
# 2         Mon Apr 1 12:00 2026   superseded  mychart-1.5  2.18.1       Upgrade complete
# 3         Mon Apr 1 14:00 2026   deployed    mychart-1.6  2.19.0       Upgrade complete

helm rollback <release> 2 -n <ns> --wait --timeout 5m
```

Rollback semantics:

- **A rollback creates a new revision** (it doesn't reset history). Revision 4 above would be a copy of revision 2's manifests.
- **`--atomic` upgrades already roll back** automatically on failure. Manual rollback is for "I deployed something broken but it appeared healthy" or "I need to revert quickly."
- **Rollback respects CRDs the same as upgrade**: CRD versions don't roll back. If a CRD field was removed in the version you're rolling forward from, the rollback may produce CRs that reference fields that no longer exist in the cluster CRD definition.
- **In GitOps**: don't `helm rollback` against a release that Flux/Argo manages. Revert the commit instead — manual rollback hides drift and the next reconcile will undo it.

## Uninstall

```bash
helm uninstall <release> -n <ns>                       # delete release + resources + history
helm uninstall <release> -n <ns> --keep-history        # delete resources, keep revision metadata
helm uninstall <release> -n <ns> --no-hooks            # skip pre/post-delete hooks
```

Things uninstall does NOT delete:

- **CRDs from `crds/`** — Helm never deletes CRDs. Delete manually if you actually want them gone (and confirm no CRs exist).
- **PVCs created by `volumeClaimTemplates`** on StatefulSets — Kubernetes retains those by default; the StatefulSet itself disappears.
- **PVs with `Retain` reclaim policy** — same idea, the PV stays.

Treat uninstall as "delete the workload, leave the data." Cleaning up storage and CRDs is a separate, deliberate step.

## Release naming

Release names are DNS-1123 labels: lowercase letters, digits, hyphens, max 53 chars (53, not 63 — Helm leaves 10 chars headroom for suffixes). They must be unique per namespace.

Conventions:

- **Match the chart name** when there's one instance per cluster (`helm install cert-manager jetstack/cert-manager`).
- **Use a discriminator suffix** when there are multiple instances (`helm install postgres-app1 …` and `helm install postgres-app2 …`).
- **Generate names sparingly** — `helm install --generate-name` produces things like `mychart-1696789012` which are awful to operate on. Better to pass an explicit name.

The release name affects the `fullname` helper, which affects every resource name in the chart. Picking a release name is committing to a resource naming scheme.

## Common task recipes

### Install a chart with a one-off override

```bash
helm upgrade --install foo ./chart -n foo --create-namespace \
  -f values.yaml \
  --set image.tag=2.18.5 \
  --atomic --wait
```

### Upgrade with a values change, preview first

```bash
helm diff upgrade foo ./chart -n foo \
  -f values.yaml -f values-staging.yaml \
  --three-way-merge --context 5

# Looks good?
helm upgrade foo ./chart -n foo \
  -f values.yaml -f values-staging.yaml \
  --atomic --wait --timeout 5m --reset-then-reuse-values
```

### Inspect what a chart will install before committing

```bash
helm pull oci://ghcr.io/myorg/charts/mychart --version 1.4.2 --untar
ls mychart/                                # see the layout
cat mychart/values.yaml                    # see all knobs

# Or without unpacking:
helm show values oci://ghcr.io/myorg/charts/mychart --version 1.4.2
helm show readme oci://ghcr.io/myorg/charts/mychart --version 1.4.2

# Render with your overrides to see what'd actually apply
helm template foo oci://ghcr.io/myorg/charts/mychart --version 1.4.2 \
  -f my-values.yaml -n foo > rendered.yaml
```

### Adopt existing resources into a Helm release

Helm 3.17+ supports `--take-ownership`:

```bash
helm install foo ./chart -n foo --take-ownership \
  -f values.yaml --dry-run=server          # confirm what gets adopted

helm install foo ./chart -n foo --take-ownership \
  -f values.yaml --atomic --wait
```

Without this flag, Helm refuses to manage a resource that already exists with conflicting ownership labels. For pre-3.17, the workaround was to add the Helm ownership annotations/labels by hand:

```bash
kubectl annotate deployment foo \
  meta.helm.sh/release-name=foo \
  meta.helm.sh/release-namespace=foo --overwrite
kubectl label deployment foo \
  app.kubernetes.io/managed-by=Helm --overwrite
```

`--take-ownership` does this automatically. Prefer it.

### Package + push a chart in CI

```bash
helm dep update ./chart                                    # refresh subcharts
helm lint ./chart --strict                                 # fail-on-warning
helm package ./chart                                       # produces chart-X.Y.Z.tgz

# Authenticate with the registry (GHA example)
echo "$GITHUB_TOKEN" | helm registry login ghcr.io -u "$GITHUB_ACTOR" --password-stdin

# Push
helm push chart-X.Y.Z.tgz oci://ghcr.io/myorg/charts
```

See [tooling.md](tooling.md) for the full chart-releaser / `cr` workflow if you're publishing to GitHub Pages instead.

## Don't / Do (using)

| Don't | Do |
|---|---|
| `helm template … \| kubectl apply -f -` for prod deploys | `helm install/upgrade --atomic --wait` (release-tracked) |
| `helm upgrade` blind | `helm diff upgrade` first |
| `helm install foo …` then `helm upgrade foo …` (separate commands in CI) | `helm upgrade --install foo …` (single idempotent command) |
| `--reuse-values` | `--reset-then-reuse-values` (3.14+) — predictable layering |
| `--set` for production overrides | `-f values-prod.yaml` checked into git |
| `helm rollback` against a GitOps-managed release | Revert the commit; let Flux/Argo reconcile |
| `helm uninstall` and "delete the PVCs too while you're at it" | Two deliberate steps; storage outlives workloads on purpose |
| Skip `--create-namespace` on first install | Include it; idempotent |
| `helm install --generate-name` in CI | Explicit `<release>` name |
| `helm install` against a cluster Flux is reconciling | Use a separate cluster (kind/k3d) for ad-hoc; commit to git for the real cluster |
| ChartMuseum for new infra | OCI (`oci://ghcr.io/...`) |
| `helm repo add` for an OCI registry | OCI installs from the URL each time; no repo-add step |
| `--insecure-skip-tls-verify` in CI | Fix the certificate chain; never bypass TLS in automation |
| `helm template … > generated.yaml` checked into git | Render in CI for validation only; let Helm own the manifests at install |
| `helm get manifest` to "see what's deployed" | `helm template` locally with the same values + `kubectl get` for live state; compare with `helm diff` |
