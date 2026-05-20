# Templates — Go template + Sprig

Helm renders chart templates with Go's `text/template` engine plus the Sprig function library, then post-processes the output through YAML parsing. Two implications: **(1) the output must be valid YAML** after rendering — whitespace, indentation, and quoting matter; **(2) you have a Turing-complete template language** with functions for nearly everything (strings, lists, dicts, regex, semver, crypto, encoding). The temptation is to abuse it; the discipline is to keep templates declarative and push logic into named templates in `_helpers.tpl`.

The most common template failure mode is whitespace bugs: a stray `{{- }}` that swallows a newline you needed, or a `nindent` that should have been `indent`, leaving a key glued to its colon. When `helm template` produces YAML that `kubeconform` rejects with "did not find expected key" or "found character that cannot start any token", look for indentation first.

## Actions, pipelines, and variables

```yaml
{{ .Values.replicaCount }}                  # action — emits the value
{{ .Values.replicaCount | default 1 }}      # pipeline — left feeds right
{{- $name := .Chart.Name -}}                # variable assignment (- trims whitespace either side)
{{ $name }}-{{ .Release.Name }}             # variables prefixed with $
```

- `{{ ... }}` — emit (the result is written into the rendered output).
- `{{- ... }}` / `{{ ... -}}` — trim leading / trailing whitespace (including a newline).
- `{{/* comment */}}` — template comment, doesn't appear in output (vs `# YAML comment` which does).
- `|` — pipeline: `{{ value | function arg1 arg2 }}` passes `value` as the **last** argument to `function`. So `default "x" .Values.y` becomes `{{ .Values.y | default "x" }}` in pipeline form (`y` is the final arg, but `default` takes the default first, so it's "default-of-y-is-x").

The pipeline rule trips people up. `printf "%s-%s" $a $b | upper` is fine. `.Values.foo | required "foo is required"` works because `required`'s signature is `(msg, value)` and the pipe makes `value` the last arg.

## Built-in objects

| Object | What |
|---|---|
| `.Values` | Merged values: chart defaults from `values.yaml`, overridden by `-f` files (in order), overridden by `--set`. Empty-but-defined keys are `nil`, not `""`. |
| `.Chart` | Chart metadata. `.Chart.Name`, `.Chart.Version`, `.Chart.AppVersion`, `.Chart.Type`, `.Chart.KubeVersion`, plus everything under `annotations:` accessible as `.Chart.Annotations.<key>` |
| `.Release` | Install-time info: `.Release.Name` (the install name), `.Release.Namespace`, `.Release.Service` (always `"Helm"`), `.Release.Revision` (revision number), `.Release.IsInstall` (bool — true on `install`), `.Release.IsUpgrade` (bool — true on `upgrade`) |
| `.Capabilities` | Cluster info: `.Capabilities.KubeVersion.Version` / `.Major` / `.Minor`, `.Capabilities.APIVersions.Has "policy/v1/PodDisruptionBudget"` (gated rendering by API availability), `.Capabilities.HelmVersion` |
| `.Files` | File access for files in the chart that are NOT in `templates/`: `.Files.Get "config/app.toml"`, `.Files.Glob "config/*.json"`, `.Files.AsConfig` / `.Files.AsSecrets` (turn a glob into a `data:` block for ConfigMap/Secret) |
| `.Template` | The current template's metadata: `.Template.Name` (path of the template being rendered), `.Template.BasePath` (the chart's `templates/`) |
| `.Subcharts` | When inside a parent chart, access to subcharts' top-level: `.Subcharts.postgresql.Values.auth.username`. Rarely needed; `import-values` is usually cleaner |

`.Values` is always merged — when you have `values.yaml` plus a `-f values-prod.yaml`, the result on disk is what `.Values` reflects. Subchart values are namespaced: a subchart `db` (after alias) reads `.Values` as its own scope, with the parent's `db:` block at the root.

## Sprig functions worth memorizing

The full set is at the [Sprig docs](https://masterminds.github.io/sprig/), but these are the load-bearing ones:

| Function | Use |
|---|---|
| `default <default> <value>` | Fall back when `value` is empty/nil. `{{ .Values.image.tag \| default .Chart.AppVersion }}` |
| `required <msg> <value>` | Fail fast if `value` is empty. `{{ required "image.repository must be set" .Values.image.repository }}` |
| `tpl <template-string> <context>` | Render a string as a template. Lets users put template syntax in `values.yaml`: `{{ tpl .Values.podAnnotations.checksum . }}` |
| `include <name> <context>` | Render a named template **as a pipeline value** (can pipe to `nindent`, `quote`, etc.). Prefer over `template`, which doesn't pipe |
| `toYaml <value>` | Serialize a value to YAML. Pair with `nindent`: `{{- toYaml .Values.resources \| nindent 12 }}` |
| `fromYaml <string>` | Parse a YAML string back to a value. Useful for working with `.Files.Get` results |
| `fromJson <string>` / `toJson <value>` | JSON variants. `toPrettyJson` for human-readable |
| `indent <n>` / `nindent <n>` | Indent by `n` spaces. `nindent` adds a leading newline first; `indent` doesn't. Use `nindent` for multi-line YAML insertion into a parent block |
| `lookup <apiVersion> <kind> <ns> <name>` | Read a live cluster resource at template time. Returns a dict on success, empty dict on miss. `{{ $svc := lookup "v1" "Service" .Release.Namespace "foo" }}` |
| `printf` | Standard Go format strings. The workhorse for composing strings |
| `quote` / `squote` | Wrap in double or single quotes. `quote` is YAML-safe — use it on any string value where the type might be ambiguous |
| `b64enc` / `b64dec` | Base64 — required for `Secret.data` (Secrets must be base64-encoded) |
| `sha256sum` / `sha1sum` / `md5sum` | Hashes. Common: `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . \| sha256sum }}` to force pod restart on configmap change |
| `randAlphaNum <n>` | Generate random — **don't use for secrets** (regenerates every render). Fine for one-off CSP nonces if you commit to a stable value via `lookup` |
| `semverCompare <range> <version>` | `{{ if semverCompare ">=1.29-0" .Capabilities.KubeVersion.Version }}` |
| `regexMatch` / `regexReplaceAll` | Regex on strings |
| `dict <k1> <v1> <k2> <v2>` | Build a map inline. `pluck` and `merge` work with dicts |
| `merge <dest> <src1> <src2>` | Right-to-left merge of dicts (dest wins). For deep-merging values overrides inside templates |
| `dig <key1> <key2> ... <default> <dict>` | Safe nested lookup with default. `{{ dig "image" "tag" "latest" .Values }}` |
| `hasKey <dict> <key>` | Check existence (vs. `default` which checks for empty) |
| `coalesce <v1> <v2> ...` | First non-empty value. Like `cmp.Or` in Go |
| `ternary <a> <b> <cond>` | Inline if — `{{ ternary "yes" "no" .Values.enabled }}` |

## Whitespace control — when to use `{{-` and `-}}`

The Helm output is YAML, so whitespace is meaningful. The rules:

- `{{-` trims preceding whitespace (back to and including the previous newline).
- `-}}` trims following whitespace (forward to and including the next newline).

| Situation | Use |
|---|---|
| A directive on its own line (`if`, `range`, `end`, `define`, etc.) | `{{- ... -}}` on both sides — otherwise the directive line leaves a blank line in the output |
| Inline value substitution inside a YAML scalar (`name: {{ .Release.Name }}`) | No trims — the YAML expects a value here, including the space |
| Inserting a multi-line block (e.g. `toYaml | nindent`) | `{{- toYaml ... | nindent N }}` — the `-` strips the previous line's whitespace; `nindent N` provides its own leading newline and indent |
| The very first action in a file | Lead with `{{- }}` so any blank line before it is removed |

A typical Deployment looks like this — note the trim placement:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount | default 1 }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      serviceAccountName: {{ include "mychart.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ .Chart.Name }}
          image: {{ include "mychart.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort | default 8080 }}
              protocol: TCP
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          {{- with .Values.env }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

The pattern `{{- with .Values.x }} ... {{- toYaml . | nindent N }} ... {{- end }}` is the right way to insert an optional structured block. `with` rebinds `.` to the value (so `toYaml .` works) and skips the whole block when the value is empty.

## Control flow

```yaml
{{- if .Values.ingress.enabled }}
# only emitted when ingress is enabled
{{- end }}

{{- if and .Values.persistence.enabled (not .Values.persistence.existingClaim) }}
# multiple conditions; `and`, `or`, `not`, `eq`, `ne`, `lt`, `gt`, `le`, `ge` are functions
{{- end }}

{{- if eq .Values.service.type "LoadBalancer" }}
loadBalancerSourceRanges:
  {{- toYaml .Values.service.loadBalancerSourceRanges | nindent 4 }}
{{- end }}

{{- range .Values.ingress.hosts }}
- host: {{ .host | quote }}
  http:
    paths:
      {{- range .paths }}
      - path: {{ .path }}
        pathType: {{ .pathType }}
        backend:
          service:
            name: {{ include "mychart.fullname" $ }}    # $ = root context
            port:
              number: {{ $.Values.service.port }}      # $.Values = root values
      {{- end }}
{{- end }}
```

Things to remember inside `range`:

- `.` is the current element. The outer scope is gone unless you saved it.
- `$` always refers to the **root context** (the one the template started with). Use `$.Values`, `$.Chart`, `$.Release` to reach outside the loop.
- You can capture index + value: `{{- range $i, $host := .Values.ingress.hosts }}`.
- `range` over a map yields `key, value` pairs: `{{- range $k, $v := .Values.annotations }}`.

## Named templates — `define`, `template`, `include`

```yaml
{{/* templates/_helpers.tpl */}}
{{- define "mychart.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end -}}
```

Call sites:

```yaml
image: {{ include "mychart.image" . }}              # GOOD — include pipes
image: {{ include "mychart.image" . | quote }}      # GOOD — pipeable
image: {{ template "mychart.image" . }}             # BAD — `template` cannot pipe
{{ template "mychart.image" . }}                    # `template` is a *statement*, not a value
```

**Always use `include`, never `template`**, because `include` returns the rendered string as a pipeline value. `template` is a statement that emits inline and can't be piped — making `nindent`, `quote`, etc. unusable.

When you `include` a template, the second argument is the context. Pass `.` for the current scope. Inside a `range`, that's the current element — if the named template needs the root scope, pass `$` instead.

### Scoping a named template

A named template gets `.` set to whatever you passed as the second argument. The convention is to pass `.` (the current root) and let the helper reach into `.Values`, `.Chart`, etc. itself. If you need to pass extra args, build a dict:

```yaml
{{- define "mychart.componentLabels" -}}
helm.sh/chart: {{ include "mychart.chart" .root }}
app.kubernetes.io/name: {{ include "mychart.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

# call site:
labels:
  {{- include "mychart.componentLabels" (dict "root" . "component" "worker") | nindent 4 }}
```

## Common patterns

### `tpl` for user-supplied template syntax

Users sometimes want to reference values inside other values — e.g. an ingress host that includes the release name. `tpl` lets a value contain template syntax that you render explicitly:

```yaml
# values.yaml
ingress:
  hosts:
    - host: "{{ .Release.Name }}.example.com"

# templates/ingress.yaml
- host: {{ tpl .host $ | quote }}
```

Without `tpl`, the value is just the literal string `"{{ .Release.Name }}.example.com"`. With `tpl`, Helm renders it as a template using `$` (the root) as context.

### `required` for must-have values

```yaml
image:
  repository: {{ required "image.repository is required" .Values.image.repository }}
```

`required` fails fast at render time with a clear message. Pair with `values.schema.json` (which catches the error even earlier).

### Force pod restart on ConfigMap change

```yaml
# templates/deployment.yaml — inside spec.template.metadata.annotations:
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

When the ConfigMap content changes, the annotation changes, and the Deployment rolls. Same pattern works for Secret-typed config (`checksum/secret`).

### `lookup` for idempotent reads

```yaml
{{- $existing := lookup "v1" "Secret" .Release.Namespace "app-db-password" }}
{{- if $existing }}
data:
  password: {{ $existing.data.password }}
{{- else }}
data:
  password: {{ randAlphaNum 32 | b64enc | quote }}   # one-time generation on first install
{{- end }}
```

`lookup` is the **only** safe way to "generate" a password in a chart — it reads the existing Secret on upgrade, so the value is stable. Without `lookup`, `randAlphaNum` on every render breaks every pod that mounted the previous Secret.

**But** the better answer is to not generate secrets in charts at all — defer to an external secret manager (1Password Operator, ESO, SOPS) and reference the resulting Secret by name. See [values.md](values.md) for the secrets pattern.

### `.Files` for sidecar configs

When you have a multi-file config to embed in a ConfigMap:

```
mychart/
└── config/
    ├── app.toml
    └── logging.json
```

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "mychart.fullname" . }}
data:
  {{- (.Files.Glob "config/*").AsConfig | nindent 2 }}
```

`AsConfig` produces `<filename>: |\n  <content>` lines suitable for a ConfigMap's `data:`. `AsSecrets` does the same but base64-encodes for `Secret.data`.

### Optional API version gating

Some resources only exist on newer Kubernetes versions. Gate rendering on capability:

```yaml
{{- if .Capabilities.APIVersions.Has "policy/v1/PodDisruptionBudget" }}
apiVersion: policy/v1
kind: PodDisruptionBudget
# ...
{{- else if .Capabilities.APIVersions.Has "policy/v1beta1/PodDisruptionBudget" }}
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
# ...
{{- end }}
```

For new charts targeting Kubernetes 1.29+, `policy/v1beta1` PDBs / `autoscaling/v2beta2` HPAs are removed — drop the fallback branch. Keep only the current GA versions in your `kubeVersion` constraint window.

### Multi-document YAML

A single template file can produce multiple manifests separated by `---`:

```yaml
{{- range .Values.workers }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" $ }}-{{ .name }}
  # ...
{{- end }}
```

Or with one resource per worker, multiple files instead — depends on whether the resources are truly similar (same template, parameterized) or just adjacent (separate files).

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| `{{ template "x" . }}` for value insertion | Can't pipe to `nindent`, `quote`, etc. | `{{ include "x" . }}` |
| `randAlphaNum` for secrets | Regenerates every render — breaks on upgrade | External secret manager; or `lookup` + fallback only on first install |
| `{{ if .Values.foo }}` for "is foo set?" when foo is a bool or 0 | `false` and `0` are falsy — you'll miss `false`-being-explicitly-set | `{{ if hasKey .Values "foo" }}` or schema-validated default |
| Hardcoded selectors like `app: {{ .Chart.Name }}` | Selectors are immutable; chart rename breaks reinstall | `selectorLabels` helper with stable subset |
| `helm.sh/chart` / `app.kubernetes.io/version` in selectors | Same — immutable, breaks on chart bump | Those go on `labels`, not `selectorLabels` |
| `{{ .Values.image.tag }}` without a default | Empty when unset → `image:` ends with `:` → ImagePullBackOff | `{{ .Values.image.tag \| default .Chart.AppVersion }}` |
| Putting logic into raw template strings | Unreadable, untestable | Extract to a named template in `_helpers.tpl` |
| Tons of nested `if/else` for envs | Same | Switch on a single `.Values.env` value, or use overlay values files |
| `nindent N` where `N` is wrong | Silent: YAML parses to something unexpected | Count the indent from the parent key, not from the line start |
| `indent` where you needed `nindent` | Output glued to the previous key | `nindent` adds the leading newline; almost always what you want |
| Stripping all whitespace with `{{-` everywhere | Output is one giant line, hard to read and debug | Trim only directive lines; leave value substitutions alone |
| Splitting one resource across multiple files | Diff hygiene suffers | One file per resource; multiple instances of the same kind via `range` or per-instance files |
| Forgetting `$` inside a `range` | `.Values` inside the range is the iteration scope, not root | Use `$.Values`, `$.Release`, `$.Chart` to reach the outer scope |
| Embedding entire YAML manifests as `.Files.Get` strings | Hard to validate, no schema check | Render them as templates so `helm template --validate` catches issues |

## Quick reference — the four "insert YAML block" idioms

```yaml
# 1. A value from values.yaml that's already a structured dict
resources:
  {{- toYaml .Values.resources | nindent 2 }}

# 2. Optional block (only emit if non-empty)
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}

# 3. A list of items
{{- range .Values.tolerations }}
- {{ toYaml . | nindent 2 }}
{{- end }}

# 4. A named template producing YAML lines
labels:
  {{- include "mychart.labels" . | nindent 2 }}
```

Get the `nindent` value right (it's the column the YAML block needs to align to, not the column the template line is on). Count from the parent key.
