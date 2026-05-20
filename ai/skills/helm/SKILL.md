---
name: helm
description: Modern Helm v3 for Kubernetes chart authoring and chart consumption. ALWAYS use when editing `Chart.yaml`, `Chart.lock`, `values.yaml`, `values.schema.json`, `_helpers.tpl`, `NOTES.txt`, anything under `templates/`/`charts/`/`crds/` in a chart, `helmfile.yaml`, or for prompts mentioning Helm, charts, `helm install`/`upgrade`/`template`/`lint`/`diff`/`package`/`push`/`pull`, `helm dep update`, OCI charts/registries, named templates, sprig, library charts, subcharts, helmfile, helm-secrets, helm-unittest, chart-testing, chart-releaser, or 'add a chart', 'fix this template', 'render with helm', 'add a values schema', 'package and push', 'rollback', 'bump chart version'. Enforces Chart v2, OCI as default distribution, `app.kubernetes.io/*` labels, immutable image tags (digest > semver), `--atomic --wait` for direct installs, `helm diff upgrade` before changes. Helm 2 / Tiller is dead. Defers to the `flux` skill for `HelmRelease` mechanics in GitOps repos.
compatibility: opencode
---

# Helm

Helm is two things stapled together: a **packaging format** (a chart — a directory of Go templates plus `Chart.yaml` and `values.yaml`) and a **release manager** (the client tracks every `helm install`/`upgrade` as a versioned, rollback-able release whose history is stored in cluster `Secret`s named `sh.helm.release.v1.<release>.v<n>`). The most useful mental model is "npm + apt for Kubernetes manifests" — charts are versioned, distributed via repos or OCI registries, depended-on by other charts, and rendered into manifests at install time. Tiller (Helm 2) is dead. Everything below assumes Helm 3.x (3.18+ as of 2026).

The most common AI failure mode here is producing 2019-era Helm: `apiVersion: v1` in `Chart.yaml`, a separate `requirements.yaml`, hooks for every lifecycle event, `randAlphaNum` to "generate" passwords (regenerates and breaks on every upgrade), CRDs scattered through `templates/` without thinking about how Helm actually installs them, `helm template … | kubectl apply -f -` instead of `helm install --atomic`, hardcoded selectors with `helm.sh/chart`/`app.kubernetes.io/version` baked in (selectors are immutable — chart upgrade breaks the Deployment), and the worst, *anything* referencing Tiller. Don't do any of that. The defaults below are non-negotiable for new code.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Author a chart — `Chart.yaml`, layout, deps, subcharts, library charts, CRDs, hooks | [charts.md](charts.md) |
| Write templates — Go template + Sprig, named templates, built-in objects, helpers | [templates.md](templates.md) |
| Structure `values.yaml` + JSON Schema validation, handle secrets | [values.md](values.md) |
| Install/upgrade/diff/rollback/template/push, OCI registries | [using.md](using.md) |
| Lint, render-validate, unittest, chart-testing, `helm test` | [testing.md](testing.md) |
| Plugins (helm-diff, helm-secrets, helm-unittest, helm-docs), helmfile, chart-releaser | [tooling.md](tooling.md) |

For one-off edits, the cheat sheets below are usually enough. Reach for the reference files when the task warrants depth.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Helm version | **3.18+** | One binary, no server-side component. Drop anything that mentions Tiller |
| Chart API | **`apiVersion: v2`** | v1 has been deprecated for years. `requirements.yaml` is dead — deps live in `Chart.yaml` |
| Distribution | **OCI registries** | `oci://ghcr.io/<org>/<chart>`. HTTP repos still work but OCI is the path forward |
| Local dev | **`helm template` + `kubeconform`** to render and validate offline | Server-side: `helm template --validate` (talks to the cluster) |
| Apply | **`helm install/upgrade --atomic --wait --timeout 5m`** | Atomic rolls back on failure; `--wait` blocks until ready. `--create-namespace` on first install |
| Preview | **`helm diff upgrade` (plugin)** before any `helm upgrade` | Plugin: `helm plugin install https://github.com/databus23/helm-diff` |
| Iteration | **Multiple `-f values-<env>.yaml`** layered later-wins, or a per-env overlay file | `--set` only for one-off CLI overrides, never the source of truth |
| Validation | **`values.schema.json`** in every chart you author | JSON Schema; Helm enforces it on install/upgrade and `helm lint` |
| Labels | **`app.kubernetes.io/*`** recommended labels on every resource | Via a `{{ include "<chart>.labels" . }}` helper |
| Secrets | **Never in `values.yaml`.** External secret manager (1Password Operator, ESO, SOPS) feeds runtime `Secret`s | App charts reference Secrets by name; don't `randAlphaNum` |
| Image refs | **Digest pin** (`image: foo@sha256:…`) > immutable semver tag > **never** `:latest` | Helper picks digest if `.Values.image.digest` is set, falls back to tag |
| Lint | **`helm lint --strict`** + **`ct lint`** (chart-testing) | `helm lint` is shallow; `ct` adds maintainer/version-bump checks |
| Unit tests | **`helm-unittest` plugin** | Snapshot-friendly, runs offline (no cluster needed) |
| Smoke tests | **`helm test` hooks** (Job in `templates/tests/`) | Runs after install via `helm test <release>` |
| Docs | **`helm-docs`** | Generates `README.md` per chart from `values.yaml` comments |
| Release | **OCI push** (`helm push oci://…`) for new infra; **chart-releaser** (`cr`) for GitHub-Pages HTTP repos | Don't bother with ChartMuseum on greenfield |
| Orchestrator | **Flux `HelmRelease`** is the GitOps default (see the `flux` skill) | `helmfile` only when you can't use Flux/Argo CD (CI ephemeral envs, lab clusters) |

## Chart anatomy at a glance

```
mychart/
├── Chart.yaml              # apiVersion v2, name, version (chart), appVersion (image)
├── Chart.lock              # generated by `helm dep update`; commit it
├── values.yaml             # default values; commented at every level (helm-docs reads these)
├── values.schema.json      # JSON Schema validating values; auto-enforced on install/upgrade/lint
├── README.md               # generated by helm-docs from values.yaml comments
├── README.md.gotmpl        # template for helm-docs
├── templates/
│   ├── _helpers.tpl        # named templates: fullname, labels, selectorLabels, image, serviceAccountName
│   ├── NOTES.txt           # post-install message; one screen max
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── pdb.yaml
│   ├── configmap.yaml
│   └── tests/
│       └── test-connection.yaml   # Job with "helm.sh/hook": test
├── crds/                   # raw CRD YAML (NOT templates) — installed once, never templated
├── charts/                 # vendored subcharts after `helm dep update` (gitignore the contents)
└── ci/                     # values overlays for `ct install` matrix
    ├── default-values.yaml
    └── ingress-values.yaml
```

The shape is opinionated: every file has one job, helpers live in `_helpers.tpl`, CRDs live in `crds/`, tests live in `templates/tests/`, and CI matrix values live in `ci/`. Charts that scatter helpers across files or pile everything into one `deployment.yaml` are harder to audit and diff.

## Modern syntax cheat sheet

| Use | Don't use |
|---|---|
| `Chart.yaml` `apiVersion: v2`, deps inline | `apiVersion: v1` + `requirements.yaml` |
| `helm dep update` and commit `Chart.lock` | `helm dependency build` after every clone |
| `oci://registry/path/chart` for distribution | ChartMuseum on new infra |
| `helm install foo ./chart --atomic --wait --timeout 5m` | `helm template … \| kubectl apply -f -` |
| `helm diff upgrade foo ./chart -f values.yaml` | "trust me, the diff is small" |
| `values.schema.json` with `required`, `type`, `enum` | runtime crash because someone typoed `replicaCount` |
| `{{ include "chart.fullname" . }}` everywhere a name is needed | `{{ .Release.Name }}-foo` hand-rolled in every file |
| `{{- toYaml .Values.resources \| nindent 12 }}` | hardcoded CPU/memory limits |
| `{{ required "image.repository is required" .Values.image.repository }}` | silent miss → broken Deployment |
| `{{- default "IfNotPresent" .Values.image.pullPolicy }}` | undefined → empty string → broken kubelet |
| `lookup "v1" "Secret" .Release.Namespace "name"` for idempotent reads of existing state | `randAlphaNum` regenerating on every upgrade |
| Library chart (`type: library`) for shared helpers | copy-pasting `_helpers.tpl` across N application charts |
| Standard `app.kubernetes.io/*` labels via helper | hand-rolled `app: foo` selectors that don't match across versions |
| Digest pin: `image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"` (fallback to tag) | `image: "{{ .Values.image.repository }}:latest"` |
| `crds/` directory for one-shot CRD install | CRDs in `templates/` (surprise on upgrade — Helm won't update them anyway) |
| `helm test <release>` with `helm.sh/hook: test` Jobs | manual smoke `kubectl exec` after deploy |
| `helm-docs` `README.md` generated from `values.yaml` comments | hand-maintained values docs that drift |
| `--reset-then-reuse-values` on `upgrade` (3.14+) | guessing between `--reset-values` and `--reuse-values` |

## Standard labels

Every resource a chart renders gets the recommended label set. Use a `_helpers.tpl` helper so the same set is applied everywhere:

```yaml
# templates/_helpers.tpl excerpt
{{- define "mychart.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "mychart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

`labels` go on `metadata.labels` of every object. `selectorLabels` go on `spec.selector.matchLabels` and `template.metadata.labels` of Deployments/StatefulSets/etc. **Selectors are immutable** in Deployments and Jobs — so the selector subset must be stable across chart upgrades. Don't include `helm.sh/chart` or `app.kubernetes.io/version` in selector labels.

See [templates.md](templates.md) for the `name`/`fullname` helpers that pair with these.

## Universal rules

These apply to chart authoring **and** chart consumption:

1. **`apiVersion: v2` in `Chart.yaml`.** No exceptions. v1 charts and `requirements.yaml` are dead.
2. **Commit `Chart.lock`. Gitignore `charts/`.** Reruns of `helm dep update` should be deterministic from the lock; the vendored subchart tarballs are build output.
3. **Pin chart versions where you consume them.** In `HelmRelease`, in a parent chart's `dependencies:`, in `helmfile.yaml` — never `version: "*"` outside of dev-loop iteration.
4. **Pin image digests in production** (`image@sha256:…`). Semver tags are fine for dev. `:latest` is never fine.
5. **`--atomic --wait` for every direct install/upgrade.** No "let it ride" deploys. Failed releases auto-roll-back.
6. **`helm diff upgrade` before `helm upgrade`.** The diff plugin is mandatory for change review.
7. **`values.schema.json` for every chart you publish.** It's the only validation users see *before* their manifest hits the API server.
8. **Never put secrets in `values.yaml`.** Reference `Secret` objects by name; let an external operator (1Password, ESO, SOPS) create the actual Secret. Don't `randAlphaNum` either — it regenerates on every upgrade.
9. **`helm template` outputs production manifests.** Render and review in CI. `helm template … | kubeconform` catches schema issues without a cluster.
10. **One named-templates helper per chart** (`templates/_helpers.tpl`). Anything that appears twice belongs there.
11. **Standard `app.kubernetes.io/*` labels** on every resource via a `labels` helper. Selectors use a stable subset (no `chart`, no `version`).
12. **CRDs in `crds/`**, not `templates/`. Be aware: Helm installs CRDs once and **never updates them** — that's a deliberate safety; for operators that ship API changes you need an out-of-band CRD upgrade step (often a parallel `helm-crds` chart or a Kustomize layer).
13. **Hooks are a last resort.** Most things people use hooks for (DB migrations, secret seeding) are better done by a real Job in `templates/` with the right ordering or an operator. Hooks bypass `helm diff` and don't roll back cleanly.
14. **`helm lint --strict` clean + `helm-unittest` green + `ct lint`/`ct install` green** before any chart change merges.

## Don't / Do

| Don't | Do |
|---|---|
| `apiVersion: v1` in `Chart.yaml` | `apiVersion: v2` |
| `requirements.yaml` for deps | `dependencies:` in `Chart.yaml` + `helm dep update` |
| Helm 2 / Tiller anything | Helm 3.x; everything is client-side |
| `helm template … \| kubectl apply -f -` | `helm install/upgrade --atomic --wait` |
| `helm upgrade` without `helm diff` first | `helm diff upgrade` first, every time |
| `version: "*"` or unpinned chart deps | exact semver, or `~ x.y.z` floor with lock |
| `:latest` image tag | digest pin (preferred) or immutable semver tag |
| Plaintext secrets in `values.yaml` | external secret manager → `Secret` referenced by name |
| `randAlphaNum 16` to "generate" a password | `lookup` an existing Secret, or fail loudly via `required` |
| Hardcoded selector labels including `chart`/`version` | stable `selectorLabels` helper; immutable across versions |
| CRDs in `templates/` | CRDs in `crds/` (install once, manage upgrades out-of-band) |
| `helm install …` without `--create-namespace` on a fresh ns | `--create-namespace` (otherwise must precreate) |
| Hooks for app DB migrations | a real Job manifest with explicit ordering, or an operator |
| Copy-pasted `_helpers.tpl` across charts | library chart (`type: library`) imported as a dependency |
| `helm template` rendered manifests committed to git | render in CI to validate; let Helm own the manifests at install |
| `ChartMuseum` for a new chart repo | OCI registry (`ghcr.io`, ECR, Harbor) |
| Hand-maintained README | `helm-docs` from `values.yaml` comments |
| `chart-releaser` for OCI charts | `helm push oci://…`; `cr` is for GitHub-Pages HTTP repos |
| Lint with just `helm lint` | `helm lint --strict` + `ct lint` + `helm-unittest` |
| `helm get manifest` to "debug" a missing resource | `helm template` locally with the same values, diff against `kubectl get` |
| Suspend Flux / pause Argo to hot-`helm upgrade` | go through git (revert / new commit); manual upgrades hide drift |
| `--set` for production values | `-f values-<env>.yaml` checked into git |

## Helm in a GitOps workflow

Most charts in this user's world get applied via Flux's `HelmRelease`, not direct `helm install`. The chart authoring rules above are identical either way — selectors, labels, schema, helpers, CRDs are all chart-level concerns. The integration layer is where it differs:

- **Don't `helm install` into a cluster Flux is reconciling.** Flux will flag drift and roll back. Use Flux's `HelmRelease` or a separate cluster.
- **`HelmRelease` apiVersion / shape / drift detection / interval** — see the `flux` skill (`helm.toolkit.fluxcd.io/v2`, `chartRef` for OCI, `driftDetection: { mode: enabled }`).
- **`helm diff` against a HelmRelease**: use `flux diff helmrelease <name> -n <ns> --path ./flux/...` rather than running `helm diff` directly.
- **Local dev for a Flux-deployed chart**: `helm template ./chart -f values-prod.yaml | kubeconform` to validate, then push and let Flux pick it up.

## When Helm isn't the right tool

Switch tools when you hit any of:

- **Stamping out per-tenant configs that differ in 4+ axes** — that's Kustomize territory. Helm + values isn't a great fit for combinatorial overlays.
- **Pure operator pattern** (the workload is itself the operator's CR, the operator manages the rest) — write the operator's CRDs and a tiny chart that installs the operator. Don't try to do the operator's job in templates.
- **GitOps with tight drift detection and lifecycle reconciliation** — pair Helm with Flux's `HelmRelease` or Argo CD's Helm support; don't imitate them in a Bash wrapper around `helm upgrade`.
- **Ad-hoc one-off manifests** — just write the manifests.

Helm is great at: shipping reusable Kubernetes applications, vendoring third-party components, packaging an internal platform's base services, and giving consumers a single `values.yaml`-shaped knob set.

## After you change anything in this skill

Run `dot install` to refresh the symlinks across all three tools. No restart needed.
