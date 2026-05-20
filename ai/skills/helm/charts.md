# Chart authoring

Everything below assumes `apiVersion: v2` (no `requirements.yaml`, no Tiller). A chart is a directory; its identity is `Chart.yaml`; its API surface to users is `values.yaml` + `values.schema.json` + the `README.md` `helm-docs` generates. Everything else is internal.

## `Chart.yaml` schema

The only required fields are `apiVersion`, `name`, and `version`. In practice you always set more — and the order of the fields matters for diff hygiene more than for correctness:

```yaml
apiVersion: v2
name: my-app
description: A short, one-sentence description of what this chart deploys.
type: application                  # application | library
version: 1.4.2                     # SemVer; chart version, bumped on EVERY chart change
appVersion: "2.18.0"               # the version of the *thing* the chart installs (quote it — strings only)
kubeVersion: ">=1.29.0-0"          # min cluster version; the trailing -0 matters for pre-releases
home: https://github.com/org/repo
icon: https://example.com/icon.png
sources:
  - https://github.com/org/my-app
keywords:
  - example
  - http
maintainers:
  - name: Team Platform
    email: platform@example.com
    url: https://example.com/team/platform

dependencies:
  - name: postgresql
    version: "16.5.2"
    repository: oci://registry-1.docker.io/bitnamicharts
    condition: postgresql.enabled
    alias: db
    import-values:
      - child: primary
        parent: postgresql.primary
    tags:
      - database

annotations:
  artifacthub.io/changes: |
    - Bumped postgresql subchart to 16.5.2
  artifacthub.io/license: Apache-2.0
  category: Database
```

### `version` vs `appVersion`

These are different and constantly conflated:

| Field | What it tracks | When you bump it |
|---|---|---|
| `version` | The chart itself (templates, defaults, helpers) | **Every** chart change. SemVer: major for breaking-default changes, minor for added knobs, patch for fixes |
| `appVersion` | The upstream app the chart installs (Docker image tag, binary release) | When the default image version moves; users can still override `image.tag` |

`appVersion` is a **string** — quote `"2.18.0"` because YAML otherwise eats trailing zeros. Inside templates, reach `.Chart.AppVersion`.

Bumping `version` is mandatory whenever the chart changes — chart-testing (`ct lint`) enforces this for changed charts and CI should fail without a bump.

### `kubeVersion`

A semver constraint validated against `.Capabilities.KubeVersion.Version` (which is the cluster's actual version when using `helm install --dry-run=server` or a real install, and the client's view otherwise). The `>=1.29.0-0` form is a quirk: without `-0`, semver pre-release tags (like `v1.29.0-eks-abc`) won't satisfy the range. Always include `-0` for floor constraints.

### `type: library`

Library charts cannot be installed standalone — they only export named templates (`{{ define }}` blocks) to be consumed by other charts that depend on them. Use when you have helper templates (labels, image refs, ingress boilerplate) reused across multiple application charts in the same monorepo or org.

```yaml
# library-chart/Chart.yaml
apiVersion: v2
name: common
type: library
version: 0.3.0
```

```yaml
# my-app/Chart.yaml
dependencies:
  - name: common
    version: 0.3.0
    repository: oci://ghcr.io/myorg/charts
```

Library charts ship `templates/_*.tpl` files only — no real resources. Consumers `{{ include "common.labels" . }}` like any other named template.

## Layout

```
mychart/
├── Chart.yaml
├── Chart.lock
├── values.yaml
├── values.schema.json
├── README.md
├── README.md.gotmpl
├── templates/
│   ├── _helpers.tpl
│   ├── NOTES.txt
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── pdb.yaml
│   ├── networkpolicy.yaml
│   └── tests/
│       └── test-connection.yaml
├── crds/
│   └── mything.yaml
├── charts/                       # gitignored, populated by `helm dep update`
└── ci/
    ├── default-values.yaml
    └── ingress-values.yaml
```

Rules:

- **One resource type per file.** `deployment.yaml`, `service.yaml`, not `manifests.yaml` with everything in it. Diff hygiene.
- **`_helpers.tpl` is the only file prefixed with `_`.** Helm skips files starting with `_` or `.` when rendering — that's how named templates avoid producing manifests.
- **`templates/tests/` is the canonical location for `helm test` hooks.** Files there should be `Pod`/`Job` resources with `"helm.sh/hook": test`.
- **`crds/` is a separate top-level directory, sibling to `templates/`.** Not under `templates/`. See the CRDs section.
- **`ci/` holds values overlays for chart-testing's `ct install` matrix.** Pattern: each `*.yaml` is a separate test scenario. Not installed by users.

## `Chart.lock` and dependencies

`Chart.lock` is generated by `helm dep update` from `Chart.yaml`'s `dependencies:`. It pins exact subchart versions and digests:

```yaml
dependencies:
  - name: postgresql
    repository: oci://registry-1.docker.io/bitnamicharts
    version: 16.5.2
digest: sha256:7f04…
generated: "2026-04-01T10:00:00Z"
```

Workflow:

```bash
# After editing Chart.yaml dependencies:
helm dep update                # writes Chart.lock + populates charts/
git add Chart.yaml Chart.lock  # commit both
echo "charts/" >> .gitignore   # vendored subchart tarballs are build output

# In CI / before install, when only the lockfile is needed:
helm dep build                 # reads Chart.lock and re-populates charts/ — does NOT update versions
```

`dep build` is for reproducibility (matches the lock). `dep update` is for moving the lock forward. Get this backwards once and you'll waste a CI run.

### Subchart wiring

The dependency block supports several useful keys beyond `name`/`version`/`repository`:

| Field | Use |
|---|---|
| `condition` | `postgresql.enabled` — a values path that toggles the subchart on/off. Multiple conditions can be comma-separated; first truthy one wins |
| `tags` | List of strings; `tags.database: true` in values enables all deps tagged `database`. Pair with `condition` cautiously — they OR with each other |
| `alias` | Mount the subchart at a different values key. Useful for vendoring the same chart twice (e.g. two redis instances) |
| `import-values` | Pull values out of the child chart up into the parent's scope. Two forms: `[{child: foo, parent: bar}]` (explicit) or `["foo.bar"]` (path-only) |

When a subchart has its own globals, set them under the alias's name in your values:

```yaml
# parent's values.yaml
db:                              # this is the alias from dependencies
  enabled: true
  auth:
    existingSecret: app-db-credentials
  primary:
    persistence:
      size: 50Gi
```

### Picking subchart versions

- **Pin exactly** in greenfield charts: `version: "16.5.2"`.
- **Tilde floor** (`version: "~16.5.0"`) only when you've audited the minor-version policy of the upstream chart and trust patch bumps.
- **Caret** (`version: "^16.0.0"`) — almost never. Most chart authors don't follow SemVer strictly.
- **Wildcards** (`version: "*"`) — never in committed code.

Renovate handles bumps; let it open PRs that bump `Chart.yaml`, regenerate `Chart.lock` in CI, and run the test matrix.

## CRDs

Helm's CRD handling is the part everyone gets wrong. The rules:

1. **Files in `crds/` (sibling to `templates/`) are installed once, on `helm install`, before the rest of the chart renders.**
2. **They are *not* templated.** Files in `crds/` are passed through verbatim — no `.Values`, no `{{ include }}`, no helpers. They're raw YAML.
3. **Helm does not update CRDs on `helm upgrade`.** Ever. The thinking is that CRD changes are destructive and shouldn't be automatic.
4. **Helm does not delete CRDs on `helm uninstall`.** Same reasoning.

This means for operators that ship API changes, you need a strategy:

- **Pattern A — separate CRDs chart**: `mything-crds/` chart with `templates/crd.yaml` (CRDs as *templates*, so they update on upgrade); the main chart has `mything/` with the workload. Install the CRDs chart, then the main chart. Used by cert-manager, prometheus-operator, others.
- **Pattern B — out-of-band**: install/upgrade CRDs with `kubectl apply -f crds/` or a Kustomize layer before installing the chart. The chart's `crds/` directory can still hold the initial set for first-time installs.
- **Pattern C — `helm upgrade --skip-crds` / Flux's `crds: CreateReplace`**: Flux's `HelmRelease` has a `crds` field that controls behavior (`Skip` | `Create` | `CreateReplace`); the latter does what Helm itself won't do.

When in doubt, **don't put CRDs in `templates/`** unless you're following Pattern A with a dedicated chart. Templates-with-CRDs in the same chart as workloads creates ordering problems (workload tries to render with a CR before the CRD exists).

## Hooks

Helm hooks are a Pod/Job/etc. with a `helm.sh/hook` annotation, run at a specific lifecycle point:

```yaml
metadata:
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"               # lower runs first; negative is fine
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

Available hooks:

| Hook | When |
|---|---|
| `pre-install`, `post-install` | Wraps the initial install |
| `pre-upgrade`, `post-upgrade` | Wraps `helm upgrade` |
| `pre-delete`, `post-delete` | Wraps `helm uninstall` |
| `pre-rollback`, `post-rollback` | Wraps `helm rollback` |
| `test` | Runs on `helm test <release>` |

### Why hooks are an anti-pattern

Hooks **bypass `helm diff`** and **don't show up in the release manifest by default**. That makes drift invisible and review impossible. They also don't roll back cleanly (a failed `post-upgrade` hook can leave you in a state where neither rollback nor re-upgrade succeeds).

Concretely:

- **DB migrations**: use an init container in the Deployment, or a Job in `templates/` with appropriate ordering, or an operator that owns the migration lifecycle. Hook-driven migrations make staged rollouts impossible.
- **Secret seeding**: use an external secret manager (1Password, ESO, SOPS). `randAlphaNum` in a `pre-install` hook regenerates every fresh install and you lose state.
- **Cluster bootstrapping**: use Job manifests with `helm.sh/hook-weight` to order them; or push the bootstrap out of Helm entirely.

**`helm test` hooks are the one legitimate use** — they're explicitly opt-in (`helm test` is a separate command), don't run during install/upgrade, and produce a clear pass/fail surface. Put them in `templates/tests/` and keep them lean.

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "mychart.fullname" . }}-test-connection"
  labels: {{- include "mychart.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox:1.36
      command: ['wget']
      args: ['{{ include "mychart.fullname" . }}:{{ .Values.service.port }}']
```

## `NOTES.txt`

Rendered after install/upgrade and shown to the user. Keep it short — one screen, focused on the next thing the user needs to do (get the URL, get a generated password, check status).

```
{{- /* templates/NOTES.txt */ -}}
1. Get the application URL:
{{- if .Values.ingress.enabled }}
   {{- range $host := .Values.ingress.hosts }}
   http{{ if $.Values.ingress.tls }}s{{ end }}://{{ $host.host }}
   {{- end }}
{{- else if contains "LoadBalancer" .Values.service.type }}
   kubectl get svc -n {{ .Release.Namespace }} {{ include "mychart.fullname" . }} -w
{{- else if contains "ClusterIP" .Values.service.type }}
   kubectl port-forward -n {{ .Release.Namespace }} svc/{{ include "mychart.fullname" . }} 8080:{{ .Values.service.port }}
{{- end }}

2. Check pod status:
   kubectl get pods -n {{ .Release.Namespace }} -l app.kubernetes.io/instance={{ .Release.Name }}
```

Don't dump architecture diagrams or full README contents into `NOTES.txt`. That's what `README.md` and `helm-docs` are for.

## `_helpers.tpl` — the canonical helpers

Every chart should define these (mirroring `helm create`):

```yaml
{{/* templates/_helpers.tpl */}}

{{/* Chart name (lowercased, truncated to 63 chars to fit DNS label limits) */}}
{{- define "mychart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name */}}
{{- define "mychart.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Chart label (for `helm.sh/chart`) */}}
{{- define "mychart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels — go on metadata.labels */}}
{{- define "mychart.labels" -}}
helm.sh/chart: {{ include "mychart.chart" . }}
{{ include "mychart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels — IMMUTABLE; go on spec.selector.matchLabels and template.metadata.labels */}}
{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* ServiceAccount name */}}
{{- define "mychart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mychart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end -}}

{{/* Container image — prefer digest, fall back to tag */}}
{{- define "mychart.image" -}}
{{- $registry := .Values.image.registry | default "" -}}
{{- $repo := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- $digest := .Values.image.digest | default "" -}}
{{- $fullRepo := ternary (printf "%s/%s" $registry $repo) $repo (ne $registry "") -}}
{{- if $digest -}}
{{- printf "%s@%s" $fullRepo $digest -}}
{{- else -}}
{{- printf "%s:%s" $fullRepo $tag -}}
{{- end -}}
{{- end -}}
```

`name` is truncated to 63 chars because that's the max length of a DNS-1123 label (Kubernetes name field). `fullname` is the same — both go into `metadata.name` of generated resources.

The `selectorLabels` definition is **load-bearing**. Selectors in `Deployment.spec.selector.matchLabels` are immutable after creation — changing the chart name, release name, or what `selectorLabels` produces requires deleting and reinstalling the Deployment. Keep this helper minimal and stable.

See [templates.md](templates.md) for how these helpers compose with the rest of the chart.

## Chart versioning policy

SemVer applied to charts, not to the app:

| Change | Bump |
|---|---|
| Bug fix in a template (no new values keys, no behavior change at default values) | patch (`1.4.2` → `1.4.3`) |
| Bump default image tag / `appVersion` (no chart-shape changes) | patch (this is a minor irritation; some orgs use minor) |
| Add a new optional values key with a backwards-compatible default | minor (`1.4.x` → `1.5.0`) |
| Change a default that alters resources users get (e.g. resources, probes, default storage size) | minor + a migration note in `annotations.artifacthub.io/changes` |
| Rename a values key, restructure values tree, remove a key | **major** (`1.x` → `2.0.0`) |
| Change selectorLabels output, or fullname helper | major (selectors are immutable — users will need to reinstall) |
| Remove a previously-rendered resource | major |
| Bump `kubeVersion` floor | major |

`ct lint` enforces the bump-on-change rule; pair with Renovate or a manual changelog process to keep the `annotations.artifacthub.io/changes` field accurate.

## Annotations worth knowing

Artifact Hub and the Helm ecosystem read several annotations from `Chart.yaml`:

```yaml
annotations:
  artifacthub.io/changes: |
    - kind: added
      description: Added support for HPA
    - kind: changed
      description: Bumped postgresql to 16.5.2
  artifacthub.io/license: Apache-2.0
  artifacthub.io/links: |
    - name: Documentation
      url: https://docs.example.com
  artifacthub.io/images: |
    - name: my-app
      image: ghcr.io/org/my-app:2.18.0
  artifacthub.io/operator: "false"
  artifacthub.io/prerelease: "false"
  artifacthub.io/containsSecurityUpdates: "false"
  category: Database
```

You don't need to set all of them. `artifacthub.io/changes` is the one you should be writing on every release.

## Chart `README.md`

Maintained by `helm-docs` from a `README.md.gotmpl` template (see [tooling.md](tooling.md)). The template references comments in `values.yaml` with `## @param` / `## @section` markers. The result is a stable, generated README that matches the actual values surface; the alternative — hand-maintained docs — drifts the moment anyone adds a values key.

## What goes in `ci/`

Per-scenario values overlays for the chart-testing matrix:

```
ci/
├── default-values.yaml          # empty file — tests the chart with defaults
├── ingress-values.yaml          # values setting ingress.enabled=true, hosts, TLS
├── persistence-values.yaml      # values enabling persistent volumes
└── ha-values.yaml               # values setting replicas, PDB, HPA
```

`ct install` walks `ci/*.yaml` and installs the chart with each overlay against an ephemeral cluster (kind/k3d in CI). Each file is independent — they don't compose. See [testing.md](testing.md) for the full chart-testing setup.

## Don't / Do (chart authoring)

| Don't | Do |
|---|---|
| `apiVersion: v1` | `apiVersion: v2` |
| `requirements.yaml` | `dependencies:` inside `Chart.yaml` |
| Skip `Chart.lock` (or worse, gitignore it) | Commit `Chart.lock`; gitignore `charts/` |
| One big `manifests.yaml` | One file per resource type |
| `_helpers.tpl` per resource file | One `_helpers.tpl` at `templates/_helpers.tpl` |
| CRDs in `templates/` | CRDs in `crds/`, or a separate `<name>-crds` chart |
| Forget `--create-namespace` on first install | Include it explicitly when installing into a fresh ns |
| `helm.sh/hook` for DB migrations / secret seeding | A real Job manifest with explicit ordering, or an operator |
| Hand-rolled `app: foo` selector | `selectorLabels` helper that stays stable across versions |
| Include `helm.sh/chart` / `app.kubernetes.io/version` in selectors | Selector keeps only `name` + `instance`; chart/version goes on `labels` only |
| Forget to bump `version` after editing templates | Bump on every chart change; `ct lint` enforces this |
| `appVersion: 2.18` (unquoted, becomes float) | `appVersion: "2.18.0"` (quoted string) |
| Wildcard subchart version | Exact semver in `Chart.yaml`; `Chart.lock` pins digest |
| Copy `_helpers.tpl` across N charts | Library chart (`type: library`) consumed as a dependency |
| Use a subchart's globals without `alias` if you need two instances | Use `alias` to mount the subchart twice with separate value scopes |
