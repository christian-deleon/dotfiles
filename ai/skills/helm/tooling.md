# Tooling — plugins, helmfile, chart-releaser, registries

Helm itself is intentionally minimal. The day-to-day workflow is built out of a small ecosystem of plugins and adjacent tools — each does one thing and composes into the standard install/upgrade/diff/publish loop. The names below are the de-facto standards as of 2026; alternatives exist but have less momentum and you'll pay an integration cost choosing them.

## Essential plugins

```bash
helm plugin install https://github.com/databus23/helm-diff
helm plugin install https://github.com/helm-unittest/helm-unittest
helm plugin install https://github.com/jkroepke/helm-secrets
helm plugin list
```

| Plugin | Purpose | When to use |
|---|---|---|
| `helm-diff` | `helm diff upgrade <release> ./chart` — preview the cluster delta before `helm upgrade` | **Always** before a production upgrade. CI / scripts should require it |
| `helm-unittest` | `helm unittest ./chart` — declarative tests against rendered templates, snapshot-friendly, no cluster needed | Every chart you author. Run in CI |
| `helm-secrets` | `helm secrets install ... -f secrets.yaml` — decrypts SOPS-encrypted values files at install time | When SOPS-encrypted secrets in git are unavoidable. Prefer external secret managers when you can |
| `helm-docs` | Generates `README.md` from `values.yaml` comments | Every chart you author. Pre-commit hook or CI step |
| `helm-git` | `helm install foo git+https://github.com/org/repo@chart-path?ref=main` — install directly from a git ref | Lab clusters, dev loops where you haven't pushed an OCI tag yet |
| `helm-cm-push` | Push to ChartMuseum HTTP repos | Only if you're stuck supporting a ChartMuseum instance — not for new infra |

### `helm-diff` flags worth knowing

```bash
helm diff upgrade <release> <chart> -n <ns> \
  -f values.yaml -f values-prod.yaml \
  --three-way-merge \           # diff vs the live cluster (catches manual edits)
  --reset-then-reuse-values \   # match the semantics of the upgrade you'd run
  --context 5 \                 # 5 lines of context around each change
  --show-secrets \              # decode Secret data in the output
  --output simple               # `simple` is colorized; `template` is parseable; `json` for tooling
```

`--three-way-merge` is the important one. Without it, you're diffing (last-Helm-state, new-Helm-state) and missing any out-of-band edits a human made to the live cluster. With it, the comparison is (live, last-applied, new) — same model `kubectl apply` uses internally.

### `helm-secrets` for SOPS-encrypted values

When you can't use an external secret manager (1Password Operator, ESO) and have to ship secrets in git, encrypt them with SOPS:

```bash
# One-time setup — encrypt a values file with age (modern; alternatives: PGP, AWS KMS, GCP KMS)
sops -e -i values-prod.secrets.yaml          # in-place encrypt

# Install using helm-secrets
helm secrets install foo ./chart -n foo \
  -f values.yaml \
  -f values-prod.secrets.yaml \              # decrypted on the fly
  --atomic --wait
```

`helm-secrets` shells out to `sops` to decrypt before passing values to Helm. The encrypted file lives in git; the decryption key (`age` private key, KMS access) lives in your CI environment / dev machines.

**This is a fallback, not a default.** In the user's stack with 1Password Operator already present, prefer that pattern (see `values.md` and the `flux` skill). Use `helm-secrets` only for scenarios where the operator route isn't available — typically when bootstrapping a cluster where the secrets operator isn't installed yet (the chicken-and-egg case).

## `helm-docs`

Generates Markdown docs from `values.yaml` comments. Install:

```bash
brew install norwoodj/tap/helm-docs                 # macOS
go install github.com/norwoodj/helm-docs/cmd/helm-docs@latest   # cross-platform
```

Run from the repo root:

```bash
helm-docs                                # processes all charts in subdirectories
helm-docs --chart-search-root charts/    # scope to a dir
helm-docs --template-files=README.md.gotmpl --document-dependency-values
```

### `README.md.gotmpl` — the template

`helm-docs` reads a Go template per chart and substitutes generated tables. Standard template:

```
{{ template "chart.header" . }}
{{ template "chart.deprecationWarning" . }}

{{ template "chart.versionBadge" . }}{{ template "chart.typeBadge" . }}{{ template "chart.appVersionBadge" . }}

{{ template "chart.description" . }}

{{ template "chart.homepageLine" . }}

## Installation

```bash
helm install my-release oci://ghcr.io/myorg/charts/{{ template "chart.name" . }} --version {{ template "chart.version" . }}
```

{{ template "chart.maintainersSection" . }}

{{ template "chart.sourcesSection" . }}

{{ template "chart.requirementsSection" . }}

{{ template "chart.valuesSection" . }}
```

Place at `<chart>/README.md.gotmpl`. `helm-docs` renders it to `<chart>/README.md`. Commit both — the `.gotmpl` is source, the `.md` is generated, and reviewers see the rendered diff.

### Comment markers in `values.yaml`

```yaml
# -- Number of pod replicas
replicaCount: 1

image:
  # -- (string) Image registry; empty for default Docker Hub
  registry: ""
  # -- Image repository
  repository: ghcr.io/myorg/my-app
  # -- @default -- `.Chart.AppVersion`
  tag: ""
  # -- Image pull policy
  pullPolicy: IfNotPresent

# -- @section Persistence
persistence:
  # -- Enable persistent storage
  enabled: false
  # -- Storage size
  # @default -- 10Gi
  size: ""
```

Markers:

| Marker | Effect |
|---|---|
| `# --` on the line above a key | Description column |
| `# -- (type)` | Override auto-detected type column |
| `# -- @default -- value` | Override the default column (useful when literal default is empty but a fallback applies) |
| `# -- @section` | Start a new section in the generated values table |
| `# -- @ignored` | Skip this key in the generated docs |
| `# -- @raw` | Don't escape Markdown in the description |

### Pre-commit hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/norwoodj/helm-docs
    rev: v1.14.2
    hooks:
      - id: helm-docs
        args:
          - --chart-search-root=charts
          - --template-files=README.md.gotmpl
```

Pair with `helm-unittest`, `helm lint`, and `kubeconform` for a comprehensive pre-commit gate.

## `helmfile`

`helmfile` is a declarative manifest for multiple Helm releases — think `terraform` for Helm, or a Compose file for a stack of charts. Useful when:

- You're not using GitOps (no Flux/Argo) and need a reproducible way to apply N charts to a cluster.
- You're orchestrating ephemeral environments (CI test clusters, lab setups, per-PR previews).
- You need to install Flux itself (chicken-and-egg).

When you have Flux/Argo, **prefer the GitOps controller's native HelmRelease/Application instead of helmfile** — running both creates two sources of truth.

```yaml
# helmfile.yaml
repositories:
  - name: jetstack
    url: https://charts.jetstack.io

releases:
  - name: cert-manager
    namespace: cert-manager
    createNamespace: true
    chart: jetstack/cert-manager
    version: 1.14.4
    atomic: true
    wait: true
    values:
      - installCRDs: true

  - name: my-app
    namespace: my-app
    createNamespace: true
    chart: oci://ghcr.io/myorg/charts/my-app
    version: 1.4.2
    atomic: true
    wait: true
    values:
      - values.yaml
      - values-{{ .Environment.Name }}.yaml
    needs:
      - cert-manager/cert-manager     # ordering: cert-manager applies first

environments:
  default:
    values:
      - environments/default.yaml
  prod:
    values:
      - environments/prod.yaml
```

Commands:

```bash
helmfile diff                   # preview all releases (uses helm-diff plugin)
helmfile apply                  # diff first, then apply only on changes — the safe default
helmfile sync                   # apply unconditionally
helmfile destroy                # uninstall everything in the file
helmfile -e prod apply          # use the prod environment overlay
helmfile -l name=my-app diff    # label-filter to a subset of releases
```

### Patterns worth knowing

- **`needs:`** declares ordering between releases. helmfile installs in dependency order.
- **`environments:`** layer values files for dev/staging/prod via `helmfile -e <name>`.
- **`hooks:`** run scripts before/after sync, diff, etc. Use sparingly — most "I need a hook" cases are actually a missing `needs:` dependency.
- **`{{ .Environment.Name }}`** in templates pulls the current environment name; useful in chart values to set environment-specific config.
- **`templates:`** define reusable release blocks. Multiple releases that share a shape (e.g. several copies of the same chart for tenants) reference a template via `inherit:`.

`helmfile` is good at: bootstrapping a cluster (Flux, cert-manager, the operators that everything else needs), orchestrating ephemeral CI environments, automating "the whole stack for this lab cluster." It's not a substitute for GitOps when GitOps is available.

## Publishing charts

### OCI registries — the modern path

```bash
# Authenticate (varies by registry)
echo "$GITHUB_TOKEN" | helm registry login ghcr.io -u "$GITHUB_ACTOR" --password-stdin

# Package
helm dep update ./chart                    # refresh subcharts + Chart.lock
helm package ./chart                       # produces chart-X.Y.Z.tgz

# Push
helm push chart-X.Y.Z.tgz oci://ghcr.io/myorg/charts
```

Registries that work:

| Registry | Notes |
|---|---|
| `ghcr.io` | Default for OSS / GitHub-hosted; auth with GITHUB_TOKEN; supports OCI charts since 2022 |
| AWS ECR | Set `aws ecr get-login-password \| helm registry login`; charts go into a separate repo (ECR creates one per chart automatically since 2023) |
| Google Artifact Registry | `gcloud auth print-access-token \| helm registry login` |
| Harbor | Supports OCI artifacts including charts; standard `helm registry login` |
| Docker Hub | Works but rate-limited for free; charts use `--namespace=<user>` semantics |
| Bitnami chart mirror | Read-only mirror of the Bitnami charts in OCI form at `registry-1.docker.io/bitnamicharts` |

### GitHub Pages + `chart-releaser` (HTTP repo path)

If you want an HTTP-served chart repo (legacy compatibility, or you have a use case where OCI doesn't fit), `chart-releaser` (`cr`) automates the publish:

```bash
# Local install
go install github.com/helm/chart-releaser/cmd/cr@latest

# Manual workflow
cr package charts/*                                  # produces .tgz files in .cr-release-packages/
cr upload --owner myorg --git-repo helm-charts \
  --token "$GITHUB_TOKEN" \
  --release-name-template '{{ .Name }}-{{ .Version }}'
cr index --owner myorg --git-repo helm-charts \
  --token "$GITHUB_TOKEN" \
  --charts-repo https://myorg.github.io/helm-charts \
  --push
```

What this does:

1. **`cr package`** — tar+gzip each chart in a known location.
2. **`cr upload`** — creates a GitHub release per chart-version, uploads the `.tgz` as a release asset.
3. **`cr index`** — fetches all release assets, generates an `index.yaml`, pushes it to the `gh-pages` branch.

The result: `https://myorg.github.io/helm-charts/index.yaml` is the served Helm repo. Consumers `helm repo add myorg https://myorg.github.io/helm-charts`.

### `chart-releaser-action` (GitHub Actions)

In CI:

```yaml
# .github/workflows/release.yaml
name: Release charts
on:
  push:
    branches: [main]
    paths: ['charts/**']

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write       # for the gh-pages push and releases
      packages: write       # if also pushing OCI
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }

      - name: Configure git
        run: |
          git config user.name "$GITHUB_ACTOR"
          git config user.email "$GITHUB_ACTOR@users.noreply.github.com"

      - uses: azure/setup-helm@v4

      # Path A — chart-releaser publishes to GitHub Pages
      - uses: helm/chart-releaser-action@v1
        with:
          charts_dir: charts
          mark_as_latest: true
        env:
          CR_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      # Path B — push the same charts to OCI in parallel
      - name: Push to OCI
        run: |
          echo "${{ secrets.GITHUB_TOKEN }}" \
            | helm registry login ghcr.io -u "$GITHUB_ACTOR" --password-stdin
          for chart in charts/*; do
            helm dependency update "$chart"
            helm package "$chart"
          done
          for tgz in *.tgz; do
            helm push "$tgz" oci://ghcr.io/${{ github.repository_owner }}/charts
          done
```

Run path A or B or both — many orgs publish to OCI as the primary and keep a GitHub Pages mirror for backwards compatibility.

## Renovate / dependabot integration

Auto-bump chart dependencies, subchart versions, and image tags:

```json
// renovate.json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "helm-values": { "fileMatch": ["values\\.ya?ml$", "values-.+\\.ya?ml$"] },
  "helmv3":      { "fileMatch": ["(^|/)Chart\\.ya?ml$"] },
  "regexManagers": [
    {
      "fileMatch": ["(^|/)values.*\\.ya?ml$"],
      "matchStrings": [
        "image:\\s*\\n\\s*repository:\\s*(?<depName>[^\\s]+)\\s*\\n\\s*tag:\\s*[\"']?(?<currentValue>[^\\s\"']+)[\"']?"
      ],
      "datasourceTemplate": "docker"
    }
  ],
  "packageRules": [
    { "matchManagers": ["helmv3"], "groupName": "Helm chart deps" },
    { "matchManagers": ["helm-values"], "groupName": "Helm values image tags" },
    { "matchDatasources": ["docker"], "pinDigests": true }
  ]
}
```

Renovate opens PRs that:

- Bump versions in `Chart.yaml` `dependencies:`.
- Bump image tags / digests in `values.yaml` (when keys match the standard `image.repository`/`image.tag` pattern).
- Update `Chart.lock` via a custom command if you configure one.

Pair with the `ct lint` + `ct install` matrix from `testing.md` so Renovate PRs auto-validate.

## Other tools worth knowing about (briefly)

| Tool | What | When |
|---|---|---|
| `kubeconform` | Offline Kubernetes-schema validator for rendered manifests | Mandatory CI gate — see `testing.md` |
| `kube-linter` | Policy/best-practice linter for manifests | Complements kubeconform; checks for missing probes, root containers, resource limits |
| `polaris` | Same niche as kube-linter, different opinion set | Pick one of polaris/kube-linter |
| `OPA Conftest` | Run Rego policies against rendered manifests | When you have a homegrown policy library |
| `helm-unittest` | Declarative tests against rendered templates | Every chart — see `testing.md` |
| `kustomize` | Manifest-overlay tool; can render Helm charts via `helmCharts:` field | When you have an existing Kustomize repo and want to vendor a Helm chart through it |
| `flux` CLI | GitOps tooling — wraps Helm install via `HelmRelease` | The user's primary deploy path — see the `flux` skill |
| `chartmuseum` | HTTP chart repo server | Don't use for new infra; OCI is the path forward |
| `helm-charts-action` (deishelm) | Older GitHub Action variants for chart publishing | Use `chart-releaser-action` instead |

## Don't / Do (tooling)

| Don't | Do |
|---|---|
| Skip `helm diff` for "small" upgrades | Plugin is required for every `helm upgrade` against a real cluster |
| Hand-maintained chart `README.md` | `helm-docs` from `values.yaml` comments + `README.md.gotmpl` |
| ChartMuseum on new infra | OCI registry (`ghcr.io`, ECR, Harbor) |
| Both helmfile and Flux/Argo on the same workload | One source of truth — pick GitOps when available |
| `chart-releaser` for OCI charts | `helm push oci://…`; `cr` is for GitHub-Pages HTTP repos |
| `helm-cm-push` plugin for new charts | OCI distribution; ChartMuseum is legacy |
| SOPS-encrypted values when an external secret operator is available | 1Password Operator / ESO; reference Secret by name |
| Renovate without `ct lint` + `ct install` in CI | Pair bot bumps with the test matrix — the bot has been wrong before |
| Mix `helm-secrets` and external secret operator in the same chart | Pick one secret-handling strategy per chart |
| Push to OCI without `helm dep update` first | Always update + commit `Chart.lock` before packaging |
| Push to OCI with a `Chart.yaml` that has unpinned dep versions | Pin in `Chart.yaml`, lock in `Chart.lock` |
| Forget the `Chart.lock` in CI publish steps | `helm dep update` regenerates the lock; commit it back or fail the publish |
