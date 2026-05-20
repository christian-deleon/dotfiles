# `values.yaml` and validation

`values.yaml` is the chart's **public API**. Every key, default, and structure is a contract — users will pin against it, override against it, and break if you rename anything. Treat it like an interface design exercise, not a junk drawer for everything the templates happen to read. The companion file is `values.schema.json`, a JSON Schema that Helm enforces on every install/upgrade/lint — when present, it catches typos and wrong types *before* manifests get to the API server.

The most common AI failure mode is producing a `values.yaml` that's a shallow flattened bag of `dotted.keys.everywhere`, no comments, no schema. Templates then have to defend against missing keys with `default` calls scattered everywhere, users have no idea what's available, and `helm-docs` has nothing to generate from. The fix is structural: group related knobs under a parent key, document every section with comments, ship a `values.schema.json`, and let the templates assume valid input.

## Canonical structure

The community-converged shape for an application chart (matches `helm create` and most well-maintained charts):

```yaml
# values.yaml

# -- Number of replicas; ignored when autoscaling.enabled is true
replicaCount: 1

image:
  # -- Image registry (optional; omit to use the default Docker Hub)
  registry: ""
  # -- Image repository
  repository: ghcr.io/myorg/my-app
  # -- Image tag; if empty, falls back to `.Chart.AppVersion`
  tag: ""
  # -- Image digest; if set, takes precedence over `tag` (recommended for prod)
  digest: ""
  # -- Image pull policy
  pullPolicy: IfNotPresent
  # -- imagePullSecrets list (names of existing Secrets)
  pullSecrets: []

# -- String to override the chart name in resource names
nameOverride: ""
# -- String to fully override the generated fullname
fullnameOverride: ""

serviceAccount:
  # -- Whether to create a ServiceAccount
  create: true
  # -- Annotations to add to the ServiceAccount
  annotations: {}
  # -- Name of the ServiceAccount; if empty and `create` is true, uses the fullname
  name: ""

# -- Annotations applied to the Pod template (rolls deployment on change)
podAnnotations: {}
# -- Labels applied to the Pod template (NOT to selector)
podLabels: {}

# -- securityContext applied at the Pod level
podSecurityContext:
  fsGroup: 1000
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

# -- securityContext applied at the container level
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
      - ALL

service:
  type: ClusterIP
  port: 80
  targetPort: 8080
  # -- Source CIDR ranges allowed when type=LoadBalancer
  loadBalancerSourceRanges: []
  annotations: {}

ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls: []
  #  - secretName: chart-example-tls
  #    hosts:
  #      - chart-example.local

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

# -- Liveness probe; set to {} to disable
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5

# -- Readiness probe; set to {} to disable
readinessProbe:
  httpGet:
    path: /readyz
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5

# -- Startup probe; set to {} to disable
startupProbe: {}

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: ""

# -- PDB; set `enabled: false` to skip
pdb:
  enabled: true
  minAvailable: ""
  maxUnavailable: 1

# -- Environment variables; supports valueFrom (secretKeyRef, configMapKeyRef, fieldRef)
env: []
#  - name: LOG_LEVEL
#    value: info
#  - name: DB_PASSWORD
#    valueFrom:
#      secretKeyRef:
#        name: app-db-credentials
#        key: password

# -- Whole-file env from a ConfigMap/Secret
envFrom: []
#  - configMapRef:
#      name: app-config
#  - secretRef:
#      name: app-secrets

# -- Extra volumes
extraVolumes: []
# -- Extra volume mounts on the main container
extraVolumeMounts: []
# -- Extra containers (init or sidecars)
extraContainers: []
extraInitContainers: []

nodeSelector: {}
tolerations: []
affinity: {}

topologySpreadConstraints: []

networkPolicy:
  enabled: false
  ingress: []
  egress: []
```

### Conventions in the structure above

1. **Every key has a comment** (`# --` is the `helm-docs` marker — it tells `helm-docs` to use the next-line value as the default and the comment as the description).
2. **Defaults are real defaults**, not empty placeholders. `pullPolicy: IfNotPresent` is the right default; `pullPolicy: ""` is not.
3. **Empty values are explicit** — `tag: ""`, `nameOverride: ""`, `tolerations: []` (not absent keys). This documents the surface and makes `.Values.X` always non-nil for the type the schema declares.
4. **Optional structured blocks have `enabled: true|false` flags.** Ingress, autoscaling, PDB, networkPolicy — all gated. Templates check `.Values.ingress.enabled` before rendering.
5. **Empty maps and lists are `{}` and `[]`**, not absent. `nodeSelector: {}` reads as "empty by default" rather than "I forgot to add this".
6. **Probes are objects, not booleans.** Disabling means `livenessProbe: {}`, not `livenessProbe: false`. The template renders `livenessProbe:` only when the value is non-empty (`{{- with .Values.livenessProbe }}`).

## `values.schema.json` — JSON Schema validation

Ship a schema in every chart. Helm validates `.Values` against it on every install, upgrade, and `helm lint`:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "title": "mychart values",
  "type": "object",
  "required": ["image"],
  "additionalProperties": false,
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 0,
      "default": 1
    },
    "image": {
      "type": "object",
      "required": ["repository"],
      "additionalProperties": false,
      "properties": {
        "registry":   { "type": "string" },
        "repository": { "type": "string", "minLength": 1 },
        "tag":        { "type": "string" },
        "digest":     { "type": "string", "pattern": "^(sha256:[a-f0-9]{64})?$" },
        "pullPolicy": { "type": "string", "enum": ["Always", "IfNotPresent", "Never"] },
        "pullSecrets": {
          "type": "array",
          "items": { "type": "object", "required": ["name"], "properties": { "name": { "type": "string" } } }
        }
      }
    },
    "nameOverride":     { "type": "string", "maxLength": 63 },
    "fullnameOverride": { "type": "string", "maxLength": 63 },
    "serviceAccount": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "create":      { "type": "boolean" },
        "annotations": { "type": "object" },
        "name":        { "type": "string" }
      }
    },
    "service": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "type":       { "type": "string", "enum": ["ClusterIP", "NodePort", "LoadBalancer"] },
        "port":       { "type": "integer", "minimum": 1, "maximum": 65535 },
        "targetPort": { "oneOf": [{ "type": "integer" }, { "type": "string" }] },
        "loadBalancerSourceRanges": { "type": "array", "items": { "type": "string", "format": "ipv4" } },
        "annotations": { "type": "object" }
      }
    },
    "resources": {
      "type": "object",
      "properties": {
        "limits":   { "type": "object" },
        "requests": { "type": "object" }
      }
    },
    "ingress": {
      "type": "object",
      "properties": {
        "enabled":   { "type": "boolean" },
        "className": { "type": "string" },
        "hosts":     { "type": "array" },
        "tls":       { "type": "array" }
      }
    },
    "autoscaling": {
      "type": "object",
      "properties": {
        "enabled":     { "type": "boolean" },
        "minReplicas": { "type": "integer", "minimum": 1 },
        "maxReplicas": { "type": "integer", "minimum": 1 }
      }
    }
  }
}
```

Rules:

- **`additionalProperties: false` at the top level** catches typos like `replicCount`. Without it, a misspelled top-level key sails through and the template just sees a missing value.
- **`required: [...]`** for anything that must exist. `image.repository` is the canonical example — no chart can install without it.
- **`enum`** for fixed sets (`pullPolicy`, `service.type`, `ingress.pathType`).
- **`oneOf` / `anyOf`** for value-type unions — `targetPort` can be int or string (port number or named port).
- **Draft-07 is the safe choice.** Helm uses [gojsonschema](https://github.com/xeipuuv/gojsonschema), which targets draft-04/06/07. Newer drafts (2019-09, 2020-12) have spotty support.

### Mutual-exclusion checks

JSON Schema can express "exactly one of these" via `oneOf`. Useful for forcing users to pick a single mode:

```json
{
  "type": "object",
  "properties": {
    "persistence": {
      "oneOf": [
        { "properties": { "existingClaim": { "type": "string", "minLength": 1 } }, "required": ["existingClaim"] },
        { "properties": { "size": { "type": "string" }, "storageClass": { "type": "string" } }, "required": ["size"] }
      ]
    }
  }
}
```

This rejects `persistence: {}` and forces either `existingClaim` or `size`.

### What schema doesn't catch

JSON Schema is structural. It can't enforce semantic invariants like "if `ingress.enabled`, `ingress.hosts` must be non-empty" (well, it can with `if/then/else` but the syntax is grim). Push those checks into `required` calls in templates:

```yaml
{{- if .Values.ingress.enabled }}
{{- if not .Values.ingress.hosts }}
{{- fail "ingress.enabled is true but ingress.hosts is empty" }}
{{- end }}
{{- end }}
```

`fail` halts rendering with a clear message — better than letting the template emit a malformed Ingress.

## Multi-file values pattern

Chart consumers layer values:

```bash
helm upgrade --install foo ./chart \
  -f values.yaml \                 # chart's defaults (helm picks this up automatically)
  -f values-prod.yaml \            # environment-specific overrides
  -f values-team-alpha.yaml \      # team-specific overrides
  --set image.tag=2.18.5           # one-off CLI override (avoid in production)
```

Later `-f` files override earlier ones, key-by-key. `--set` overrides everything. Don't put production overrides in `--set` — they're invisible to git review.

For chart authors: design `values.yaml` so that **defaults are appropriate for development**, and environment overlays *narrow* the surface for prod (set replicas higher, enable HPA, lock down probes, etc.). The opposite — defaults that crash unless every key is overridden — pushes complexity onto every user.

### Layout for environment values

In an app repo that consumes a chart:

```
deploy/
├── values.yaml                # baseline; matches chart defaults except for known divergence
├── values-dev.yaml
├── values-staging.yaml
└── values-prod.yaml
```

Or in a Flux GitOps repo: `flux/apps/base/<app>/helmrelease.yaml` carries the inline `values:` block; per-cluster overlay directories override that block via Kustomize patches. See the `flux` skill for the full pattern.

## `--set` semantics — read before you use it

`--set` and `--set-string` have parsing quirks worth knowing:

- **`--set foo.bar=baz`** sets `foo.bar` to the string `"baz"`. Helm tries to infer the type — `--set replicas=3` becomes an int, `--set replicas=3.0` becomes a float, `--set replicas=true` becomes a bool. **Use `--set-string foo=3` to force string.**
- **`--set list[0].name=foo`** sets indexed list elements. `--set 'list={a,b,c}'` sets a string array. Lists in `--set` are fragile — the order matters and re-runs can re-index.
- **`--set foo.bar.baz=x` creates intermediate maps** if they didn't exist. Convenient and dangerous (typos create new paths instead of erroring).
- **Commas separate top-level keys**: `--set a=1,b=2`. Escape commas in values with `\,`.
- **`--set-file foo=./bar.yaml`** loads the file's content as a string into `foo`. Useful for shoving a TLS key or large config into a single value.
- **`--set-json 'foo={"a":1}'`** (Helm 3.10+) sets a value from a JSON blob — useful for nested structures `--set` can't handle.

**Rule of thumb**: `-f values-*.yaml` for anything reviewable. `--set` only for one-off CLI plumbing (tests, debug installs, ephemeral CI).

## Secrets — what NOT to put in `values.yaml`

Plaintext credentials don't go in `values.yaml`. They don't go in `values-prod.yaml`. They don't go in `--set`. Patterns from best to worst:

| Pattern | Where the secret lives | Chart references it via |
|---|---|---|
| **External secret operator** (1Password Operator, ESO, Sealed Secrets) | Operator-managed Secret in cluster | `valueFrom.secretKeyRef` / `envFrom.secretRef` / `volumes.secret.secretName` in `values.yaml`, naming the Secret |
| **`existingSecret` pattern** | A precreated Secret (any source) | `.Values.auth.existingSecret` names it; template references via `secretKeyRef` |
| **Helm `lookup` + first-install generation** | Cluster Secret (created on first install, reused thereafter) | Template uses `lookup` to read existing, `randAlphaNum` only if missing |
| **SOPS-encrypted values** | Encrypted `values-prod.yaml` in git | `helm-secrets` plugin decrypts at install time |
| **Plaintext in `values.yaml`** | Git repo | NEVER — committed credentials are credentials someone has |
| **`--set` from a CI variable** | CI environment | OK for ephemeral envs only, NEVER for prod |

In this user's stack, **1Password Operator + emberstack/reflector** is the convention (see the `flux` skill for the operator setup). Charts reference Secrets by name; the operator materializes the actual Secret from 1Password.

### `existingSecret` pattern

The chart accepts the name of a pre-existing Secret:

```yaml
# values.yaml
auth:
  # -- Name of an existing Secret with keys: username, password
  existingSecret: ""
  # -- Used only when existingSecret is empty (for dev / first-install bootstrap)
  username: admin
  password: ""
```

```yaml
# templates/secret.yaml
{{- if not .Values.auth.existingSecret }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "mychart.fullname" . }}-auth
  labels: {{- include "mychart.labels" . | nindent 4 }}
type: Opaque
stringData:
  username: {{ .Values.auth.username }}
  password: {{ required "auth.password or auth.existingSecret is required" .Values.auth.password }}
{{- end }}
```

```yaml
# templates/deployment.yaml — env block:
env:
  - name: AUTH_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ default (printf "%s-auth" (include "mychart.fullname" .)) .Values.auth.existingSecret }}
        key: password
```

Users in production point `auth.existingSecret` at an externally-managed Secret. Users in dev set `auth.password` directly and let the chart create the Secret.

## Chart values vs subchart values

When the chart depends on subcharts, those subcharts have their own `values.yaml`. The parent overrides them via a nested block:

```yaml
# parent values.yaml
db:                              # this matches the dependency name (or alias)
  enabled: true
  auth:
    existingSecret: app-db-credentials
  primary:
    persistence:
      size: 50Gi
```

If you used `alias: db` in `Chart.yaml`, the values key is `db`. Otherwise it's the subchart's `name`.

### Globals — use sparingly

The `global:` key is special: it's passed to every subchart. Use it for things that genuinely apply across the whole release (image pull secrets, storage class, image registry mirror):

```yaml
global:
  imageRegistry: my-registry.example.com
  imagePullSecrets:
    - name: my-pull-secret
  storageClass: fast-ssd
```

Every well-behaved Bitnami-style chart honors `global.imageRegistry` and `global.imagePullSecrets`. Don't put app-specific config under `global:` — it leaks into subcharts that don't need it.

## Documenting values for `helm-docs`

`helm-docs` reads structured comments from `values.yaml` and generates a Markdown table in `README.md`. The conventions:

```yaml
# -- Description of replicaCount, can span
# -- multiple `# --` lines.
replicaCount: 1

image:
  # -- (string) The image registry
  registry: ""
  # -- The image repository
  repository: ghcr.io/myorg/my-app

# -- @section Persistence
# -- @section Persistence configuration for the database

persistence:
  # -- @default -- 10Gi
  size: ""
```

Markers:

| Marker | Effect |
|---|---|
| `# --` on the line directly above a key | The comment text becomes the description column |
| `# -- (type)` | Override the auto-detected type |
| `# -- @default -- value` | Override the default shown (useful when the literal default is empty but a fallback applies) |
| `# -- @section` | Start a new section in the generated table |

See [tooling.md](tooling.md) for the `helm-docs` setup, `.helmdocsignore`, and `README.md.gotmpl` template.

## Don't / Do (values)

| Don't | Do |
|---|---|
| Plaintext secrets in `values.yaml` / `values-prod.yaml` | External secret manager → Secret referenced by name |
| Undocumented values keys | Every key has a `# --` comment for `helm-docs` |
| Flatten everything: `db.host`, `db.port`, `db.user` separately | Group: `db: { host: …, port: …, user: … }` |
| Skip `values.schema.json` | Ship a schema with `required`/`enum`/`type`/`additionalProperties: false` |
| Absent keys for "optional" maps/lists | Explicit `{}` / `[]` defaults |
| Bool flag named `disableFoo` | Bool flag named `foo.enabled` |
| `tag: latest` as a default | `tag: ""` (template falls back to `.Chart.AppVersion`) |
| `--set password=secret` for prod | `existingSecret` or external secret manager |
| `--set tolerations[0].key=...` | `-f values.yaml` with the structured value |
| `global: { mySpecificThing: x }` for app-level config | Top-level key; reserve `global:` for cross-subchart concerns |
| Empty `values.schema.json` to "satisfy the linter" | A real schema with `additionalProperties: false` and `required` |
| `randAlphaNum` for production passwords | External secret manager; `lookup` + fallback for first-install dev only |
| Inconsistent shape between similar charts in the same monorepo | Library chart for shared defaults + helpers; or a documented template `values.yaml` |
