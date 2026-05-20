# Testing — lint, render-validate, unit, smoke

A chart's testing surface has four distinct layers and skipping any one will eventually bite you:

| Layer | Tool | What it catches | Where it runs |
|---|---|---|---|
| **Lint** | `helm lint --strict` + `ct lint` | YAML syntax, missing required fields, chart version not bumped, malformed `Chart.yaml`, schema validation failures | CI on every PR — fast |
| **Render-validate** | `helm template` + `kubeconform` (offline) or `--validate` (server) | Kubernetes-schema validity of the rendered manifests | CI on every PR — fast offline, slower with cluster |
| **Unit** | `helm-unittest` plugin | Template behavior across value overrides — "does this render produce these fields?" | CI on every PR — fast (no cluster) |
| **Install / smoke** | `ct install` (kind/k3d cluster) + `helm test` | Resources actually reconcile, app starts, contracts hold end-to-end | CI on PR for changed charts, daily for everything |

Run all four. `helm lint` alone is shallow — it catches obvious mistakes but won't tell you that your Deployment's `strategy.rollingUpdate.maxSurge` is set to a string that the API server will reject, or that your generic enum `Always|IfNotPresent|Never` value has a typo. Unit and install tests cover what lint can't see.

## `helm lint`

```bash
helm lint ./chart                    # checks chart, prints warnings + errors
helm lint ./chart --strict           # treat warnings as errors (CI default)
helm lint ./chart --with-subcharts   # recursively lint subcharts
helm lint ./chart -f values-prod.yaml -f values-staging.yaml  # lint with overrides
```

What `helm lint --strict` catches:

- Missing `Chart.yaml` fields (`apiVersion`, `name`, `version`).
- Invalid SemVer in `version`.
- `apiVersion: v1` (warns; you should be on `v2`).
- YAML parse errors in `values.yaml`, `Chart.yaml`, templates.
- `values.schema.json` violations against `values.yaml`.
- Template rendering errors (missing required values, unparseable Go template).
- Manifest-level issues: missing `metadata.name`, malformed selectors (sometimes).
- Icon URL not reachable (warns).

What `helm lint` does NOT catch:

- Kubernetes API schema violations (wrong field types, removed APIs, invalid enum values).
- Selector immutability issues across chart versions.
- Hooks that won't roll back cleanly.
- Subtle whitespace / indent bugs that still parse as valid YAML but produce wrong structure.

That's why you pair it with `kubeconform` and `helm-unittest`.

### Linting against multiple value overrides

A chart needs to render correctly across the value combinations real users send. Lint each `ci/*.yaml` overlay:

```bash
for f in chart/ci/*.yaml; do
  helm lint ./chart --strict -f "$f" || exit 1
done
```

`ct lint` (below) does this automatically and adds version-bump checks.

## `kubeconform` — offline schema validation

`kubeconform` validates rendered manifests against the Kubernetes OpenAPI schema for a specific cluster version. No cluster required; fast; perfect for CI on every PR:

```bash
helm template foo ./chart -n foo -f values-prod.yaml \
  | kubeconform \
      -strict \
      -summary \
      -kubernetes-version 1.30.0 \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

Notes:

- **`-strict` rejects `additionalProperties`** — catches misspelled fields. Always on in CI.
- **`-summary` prints a count per kind** at the end. Use it in CI logs.
- **`-kubernetes-version`** picks which schema set to use. Match it to your target cluster's version (or run multiple times for a matrix).
- **CRD schemas** (`-schema-location` with a CRD catalog URL) — required to validate custom resources. Without it, CRs render as `additionalProperties` violations under `-strict`. The Datree CRDs catalog is the convention; if you have first-party CRDs, host the JSON Schema yourself and point at it.
- **Exit non-zero on failure** — `kubeconform` exits 1 on any validation error, which is the right behavior for CI.

Alternatives that exist: `kubeval` (unmaintained — don't use), `kube-linter` (style/policy, complements kubeconform but doesn't replace it).

### `helm template --validate` (server-side)

When you have a target cluster available (kind/k3d in CI, or a real dev cluster), `--validate` is stricter than `kubeconform`:

```bash
helm template foo ./chart -n foo -f values.yaml --validate
```

It sends every rendered manifest to the API server with `dryRun=All`. Catches:

- CRD references where the CRD isn't installed in the cluster.
- Admission webhook rejections (e.g. PSA violations, OPA Gatekeeper policy).
- Defaulting that `kubeconform` can't see (the API server fills in defaults during dry-run).

Use `kubeconform` for fast PR feedback (no cluster); use `--validate` against a target cluster before the actual apply.

## `helm-unittest` plugin

`helm-unittest` runs declarative tests against rendered templates without touching a cluster. Snapshot-friendly, fast, and the right tool for "this chart should produce this Deployment when these values are set":

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
```

Tests live in `<chart>/tests/`:

```yaml
# chart/tests/deployment_test.yaml
suite: deployment
templates:
  - templates/deployment.yaml
tests:
  - it: should render with default values
    asserts:
      - isKind:
          of: Deployment
      - equal:
          path: spec.replicas
          value: 1
      - equal:
          path: spec.template.spec.containers[0].image
          value: ghcr.io/myorg/my-app:2.18.0

  - it: should set replicas from values
    set:
      replicaCount: 3
    asserts:
      - equal:
          path: spec.replicas
          value: 3

  - it: should pick digest over tag when set
    set:
      image.digest: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    asserts:
      - matchRegex:
          path: spec.template.spec.containers[0].image
          pattern: '@sha256:[a-f0-9]{64}$'

  - it: should fail without image.repository
    set:
      image.repository: null
    asserts:
      - failedTemplate:
          errorMessage: "image.repository is required"

  - it: rendered Deployment matches snapshot
    asserts:
      - matchSnapshot: {}     # writes / compares __snapshot__/<test>.yaml
```

Run:

```bash
helm unittest ./chart                       # all tests
helm unittest ./chart -f 'tests/*_test.yaml'
helm unittest ./chart --update-snapshot     # regenerate snapshots after intentional changes
helm unittest ./chart --color
```

### Assertion types worth knowing

| Assertion | Use |
|---|---|
| `equal: { path, value }` | Exact value at a JSON path |
| `notEqual: { path, value }` | Inverse |
| `isKind: { of }` | Resource kind |
| `isAPIVersion: { of }` | apiVersion |
| `isNotNull: { path }` / `isNull: { path }` | Existence checks |
| `hasDocuments: { count }` | Multi-document YAML — how many manifests rendered |
| `matchRegex: { path, pattern }` | Regex match on a string |
| `contains: { path, content }` | Array contains element |
| `notContains` / `notExists` | Inverses |
| `failedTemplate: { errorMessage }` | Render is expected to fail with this message — for `required`/`fail` assertions |
| `matchSnapshot: { path }` | Snapshot diff at path; without path, the whole render |
| `subset: { path, content }` | Object at path contains these keys (other keys are allowed) |

### When to use snapshots vs. specific asserts

- **Specific asserts** for behavior you care about: "if HPA is enabled, replicas come from autoscaling.minReplicas, not replicaCount." These document intent.
- **Snapshots** for catch-all regression: "rendering with defaults shouldn't change unintentionally." Pair with specific asserts; don't rely on snapshots alone (they catch *any* change but don't tell you which changes matter).

Snapshots live in `<chart>/tests/__snapshot__/`. Commit them. Update intentionally with `--update-snapshot` and review the diff.

## `chart-testing` (`ct`)

`ct` is a tool that orchestrates lint + install across charts in a monorepo, running only on charts that actually changed:

```bash
ct lint --config ct.yaml                          # lint changed charts
ct install --config ct.yaml                       # install changed charts on a real cluster
ct list-changed --config ct.yaml                  # print which charts changed vs. main
```

Config (`.github/ct.yaml` or `ct.yaml`):

```yaml
target-branch: main
chart-dirs:
  - charts
chart-repos:
  - bitnami=https://charts.bitnami.com/bitnami
helm-extra-args: --timeout 5m
check-version-increment: true        # fail if changed chart's version wasn't bumped
validate-maintainers: true
exclude-deprecated: true
```

What `ct lint` adds over `helm lint --strict`:

- **Version-bump check** — chart `version` must increase if any file in the chart dir changed. Caught at PR time, not at release time.
- **Maintainer validation** — `Chart.yaml` `maintainers:` must be non-empty.
- **Deprecation check** — chart marked `deprecated: true` in `Chart.yaml` is skipped (with `exclude-deprecated: true`).
- **Cross-chart consistency** — runs the same lint config across every changed chart.

What `ct install` does:

1. Spins up an ephemeral cluster (kind/k3d/k3s — you provide it, `ct` doesn't create the cluster).
2. For each changed chart and each `ci/*.yaml` overlay (or just the defaults if there's no `ci/`):
   - `helm install` with `--wait --timeout` (ct's defaults are reasonable).
   - Runs `helm test` if the chart ships test hooks.
   - On failure, prints logs / events for triage.
3. Uninstalls + repeats for each overlay.

This is the canonical "actually deploy and see if it works" gate.

### `ct install` in CI (GitHub Actions example)

```yaml
# .github/workflows/lint-test.yaml
name: Lint and test charts
on:
  pull_request:
    paths:
      - 'charts/**'

jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0     # ct needs full history to diff against target-branch

      - uses: azure/setup-helm@v4
      - uses: helm/chart-testing-action@v2

      - run: ct lint --config ct.yaml

      - if: steps.list-changed.outputs.changed == 'true'
        uses: helm/kind-action@v1
        with:
          version: v0.27.0
          node_image: kindest/node:v1.30.0

      - if: steps.list-changed.outputs.changed == 'true'
        run: ct install --config ct.yaml
```

### `ci/` value overlays

In the chart dir:

```
charts/mychart/
└── ci/
    ├── default-values.yaml          # often empty — test the defaults
    ├── ingress-enabled-values.yaml
    ├── persistence-enabled-values.yaml
    └── autoscaling-values.yaml
```

`ct install` walks `ci/*.yaml` and installs the chart with each overlay independently. The overlays should exercise distinct code paths: enabling ingress, enabling persistence, enabling autoscaling, switching service type, etc. They don't compose — each is a separate test scenario.

## `helm test` — smoke tests after install

A chart's own smoke tests live in `templates/tests/` as Pod/Job manifests with the `helm.sh/hook: test` annotation:

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "mychart.fullname" . }}-test-connection"
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox:1.36
      command: ["wget"]
      args:
        - "-q"
        - "-O-"
        - "{{ include "mychart.fullname" . }}:{{ .Values.service.port }}/healthz"
```

Run after install:

```bash
helm test <release> -n <ns>
```

`helm test` creates the test Pod, waits for it to complete, and reports pass/fail. Useful for:

- HTTP smoke checks against the rendered Service.
- Database connection / migration tests when secrets are wired correctly.
- End-to-end "request hits the app and returns 200" verification in CI.

`ct install` runs `helm test` automatically. In production after an upgrade, also call it explicitly when the chart ships meaningful tests.

Keep tests small and fast. A test Pod that takes 5 minutes to run breaks the install loop.

## End-to-end CI pattern (monorepo of charts)

```yaml
# .github/workflows/charts.yaml
name: Charts CI
on:
  pull_request:
    paths: ['charts/**']
  push:
    branches: [main]
    paths: ['charts/**']

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: azure/setup-helm@v4
      - uses: helm/chart-testing-action@v2

      - name: List changed charts
        id: list-changed
        run: |
          changed=$(ct list-changed --config ct.yaml)
          if [ -n "$changed" ]; then
            echo "changed=true" >> "$GITHUB_OUTPUT"
            echo "charts<<EOF" >> "$GITHUB_OUTPUT"
            echo "$changed" >> "$GITHUB_OUTPUT"
            echo "EOF" >> "$GITHUB_OUTPUT"
          fi

      - name: ct lint (with version bump check)
        run: ct lint --config ct.yaml

      - name: helm lint --strict on each changed chart
        if: steps.list-changed.outputs.changed == 'true'
        run: |
          while IFS= read -r chart; do
            helm dependency update "$chart"
            helm lint "$chart" --strict
            for f in "$chart"/ci/*.yaml; do
              [ -f "$f" ] || continue
              helm lint "$chart" --strict -f "$f"
            done
          done <<< "${{ steps.list-changed.outputs.charts }}"

      - name: helm-unittest
        if: steps.list-changed.outputs.changed == 'true'
        run: |
          helm plugin install https://github.com/helm-unittest/helm-unittest
          while IFS= read -r chart; do
            helm unittest "$chart"
          done <<< "${{ steps.list-changed.outputs.charts }}"

      - name: Render + kubeconform
        if: steps.list-changed.outputs.changed == 'true'
        run: |
          curl -sSL https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz
          while IFS= read -r chart; do
            for f in "$chart"/ci/*.yaml; do
              [ -f "$f" ] || continue
              helm template release "$chart" -f "$f" \
                | ./kubeconform -strict -summary \
                    -kubernetes-version 1.30.0 \
                    -schema-location default \
                    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
            done
          done <<< "${{ steps.list-changed.outputs.charts }}"

  install:
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: azure/setup-helm@v4
      - uses: helm/chart-testing-action@v2
      - uses: helm/kind-action@v1
        with:
          version: v0.27.0
          node_image: kindest/node:v1.30.0
      - run: ct install --config ct.yaml
```

This is the canonical four-layer gate. Lint catches syntax. helm-unittest catches behavioral regressions. kubeconform catches schema violations. `ct install` catches "it doesn't actually start."

## Don't / Do (testing)

| Don't | Do |
|---|---|
| `helm lint` (non-strict) as the only CI check | `--strict` plus the rest of the four-layer gate |
| Skip `kubeconform` because "there's a kind cluster in CI anyway" | Run both — kubeconform is fast offline; cluster install catches admission/webhook issues |
| Snapshot-only tests in `helm-unittest` | Specific asserts for intent + snapshots for catch-all regression |
| Commit snapshots without reviewing the diff | `--update-snapshot` only after looking at what changed |
| Per-chart ad-hoc test scripts | `ct lint` + `ct install` driven by `ci/*.yaml` overlays |
| Test hooks that take minutes | Small, fast smoke checks; defer long suites to a separate job |
| `kubeval` | `kubeconform` (kubeval is unmaintained) |
| Forget `-schema-location` for CRDs | Add the Datree CRDs catalog or your own schema host |
| Forget to bump chart `version` between PRs | `ct lint` with `check-version-increment: true` catches this |
| Empty `ci/` directory | At least `ci/default-values.yaml` (can be empty file, but the file presence triggers a test run) |
| Tests that hit external networks (DNS, public APIs) | Self-contained tests against the chart's own Service / mocks |
| Test Pods that don't set `restartPolicy: Never` | Always `Never` — failed test should fail, not restart-loop |
