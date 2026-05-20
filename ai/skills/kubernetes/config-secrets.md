# Configuration and Secrets

Two resources, one rule of thumb: **`ConfigMap` for things safe to read, `Secret` for things you'd be unhappy to see in a `kubectl get` audit log**. Both end up as files or environment variables inside the pod. Both are namespace-scoped. Both can be projected as volumes — and almost always should be.

Secret storage in Kubernetes is base64-encoded, not encrypted. Cluster operators need to enable **etcd encryption at rest** (KMS provider) for `Secret` to be meaningfully different from `ConfigMap` from a storage-on-disk perspective. Treat that as a cluster-install concern; if you're not sure, ask.

## ConfigMap — shapes

Three styles, pick by use case:

```yaml
# 1. Key-value (best for env vars and small config keys)
apiVersion: v1
kind: ConfigMap
metadata: { name: checkout, namespace: checkout }
data:
  log_level: info
  port: "8080"                                    # everything is a string
  feature_x_enabled: "true"
immutable: true                                   # see below
```

```yaml
# 2. Files (best for config files mounted as volumes)
apiVersion: v1
kind: ConfigMap
metadata: { name: checkout-config, namespace: checkout }
data:
  config.yaml: |
    server:
      addr: :8080
      timeout: 30s
    db:
      pool_size: 20
```

```yaml
# 3. Binary data (avoid; use a Secret or store in object storage)
apiVersion: v1
kind: ConfigMap
metadata: { name: assets }
binaryData:
  blob.bin: <base64>
```

### Immutable ConfigMaps and Secrets

```yaml
immutable: true
```

A `ConfigMap` or `Secret` flagged `immutable: true` cannot be updated — only deleted and recreated. Two consequences:

- The kubelet doesn't have to watch it for changes, which cuts API server load at scale.
- Updating it means **renaming** it (e.g. `checkout-v2`) and rolling Deployments to reference the new name — this **forces a rollout**, which is what you wanted anyway.

For config that should change atomically with a deploy (most config), use immutable + versioned names. Helm's checksum annotation pattern achieves the same thing without rename. Defer to the `helm` skill for the chart-side mechanics.

## Consuming config in a Pod

Two delivery modes, prefer files:

### Env vars (small, simple, can't update)

```yaml
spec:
  containers:
    - name: app
      envFrom:
        - configMapRef:
            name: checkout                        # all keys become env vars
        - secretRef:
            name: checkout-db                     # same for secrets
      env:
        - name: PORT                              # override or pick one key
          valueFrom:
            configMapKeyRef:
              name: checkout
              key: port
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: checkout-db
              key: password
              optional: false                     # fail to start if missing
```

Env vars are **frozen at pod start**. Updating a `ConfigMap` does not update env vars in running pods. Restart the pod (rollout) to pick up changes.

### Volume mounts (preferred — supports live updates and files)

```yaml
spec:
  containers:
    - name: app
      volumeMounts:
        - name: config
          mountPath: /etc/checkout
          readOnly: true
        - name: tls
          mountPath: /etc/checkout/tls
          readOnly: true
  volumes:
    - name: config
      configMap:
        name: checkout-config
        items:
          - key: config.yaml
            path: config.yaml                     # /etc/checkout/config.yaml
        defaultMode: 0o444
    - name: tls
      secret:
        secretName: checkout-tls
        defaultMode: 0o400                        # 0400 — read-only for owner
```

Volume-mounted `ConfigMap` / `Secret` values **do** update in-place when the resource changes — the kubelet refreshes them on a polling interval (~60-90s). Your app needs to handle that (re-read on file change, SIGHUP, or restart-on-change via a controller like Reloader).

### Projected volumes — many sources, one mount

```yaml
volumes:
  - name: bundle
    projected:
      sources:
        - configMap:
            name: checkout-config
            items: [{ key: config.yaml, path: config.yaml }]
        - secret:
            name: checkout-db
            items: [{ key: password, path: db-password }]
        - serviceAccountToken:
            audience: vault                       # bound, audience-scoped, auto-rotated
            expirationSeconds: 3600
            path: vault-token
```

`projected` is the right shape when a single mount path needs to combine multiple sources. Especially useful for **bound service account tokens** (`serviceAccountToken`), which are how new code authenticates pods to external systems (Vault, cloud IAM) without long-lived secrets.

## Secrets — the real options

Native `kind: Secret` is fine for storing values; the question is **how secrets get there**. Choose by what's already in the repo:

| Pattern | Use when | Source of truth |
|---|---|---|
| **1Password Operator + Reflector** | Default for this user (matches `flux` skill) | Items in a 1Password vault, materialized as `Secret` via `OnePasswordItem` CRD |
| **External Secrets Operator (ESO)** | When the project already uses ESO + a backend (Vault, AWS Secrets Manager, GCP Secret Manager) | `ExternalSecret` CRD references a `SecretStore` / `ClusterSecretStore` |
| **SOPS-encrypted secrets in git** | When the project uses SOPS + age/KMS, decrypted by Flux | `.enc.yaml` files in git, decrypted at apply time |
| **CSI Secrets Store driver** | When pods should never see a `Secret` object — mount values directly from Vault / AWS Secrets Manager / etc. | The external secret store, materialized as a tmpfs mount |
| Plain `kind: Secret` checked into git | **Never** | — |

Defer the GitOps + 1Password specifics to the **`flux` skill**. The shape that matters here:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: checkout-db                               # operator materializes a Secret with this name
  namespace: checkout
spec:
  itemPath: "vaults/<vault-uuid>/items/<item-uuid>"
```

The operator creates a regular `Secret` named `checkout-db` in the same namespace. Pods consume it like any other `Secret`.

### Cross-namespace replication

Reflector annotations let one source `Secret` be mirrored into other namespaces:

```yaml
# Source (in postgres namespace)
apiVersion: v1
kind: Secret
metadata:
  name: cluster-app
  namespace: postgres
  annotations:
    reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
    reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "checkout,orders"
    reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
    reflector.v1.k8s.emberstack.com/reflection-auto-namespaces: "checkout,orders"
type: Opaque
data: { ... }
```

Common case: a Postgres operator creates a credentials `Secret` in `postgres`, the consuming app lives in `checkout`. Reflector keeps them in sync.

## Secret types — when each matters

| `type:` | Required keys | Use |
|---|---|---|
| `Opaque` | any | Catch-all; most user secrets |
| `kubernetes.io/tls` | `tls.crt`, `tls.key` | TLS certs (cert-manager produces these) |
| `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` | Image pull secrets |
| `kubernetes.io/service-account-token` | (auto-populated) | Legacy SA token — bound tokens are preferred |
| `kubernetes.io/basic-auth` | `username`, `password` | Basic-auth credentials (rarely needed) |
| `kubernetes.io/ssh-auth` | `ssh-privatekey` | Private SSH key |

Use the **typed** form when one exists — controllers and admission policies look at `type`.

## Image pull secrets

```yaml
apiVersion: v1
kind: Secret
type: kubernetes.io/dockerconfigjson
metadata:
  name: ghcr-pull
  namespace: checkout
data:
  .dockerconfigjson: <base64>
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: checkout
  namespace: checkout
imagePullSecrets:
  - name: ghcr-pull
```

Attaching the pull secret to the **ServiceAccount** is preferred over per-Pod `imagePullSecrets:`. Pods using that SA inherit it automatically.

For multi-namespace reuse, reflect the pull secret rather than copying it.

## When config changes mid-pod

Two patterns to react to a `ConfigMap` / `Secret` change:

1. **App reads the mounted file on every request** (or on SIGHUP, or with a file-watcher). No restart needed. Best for hot-reloadable settings.
2. **Restart the pod when the config changes.** Use [stakater/Reloader](https://github.com/stakater/Reloader) — annotate the Deployment:
   ```yaml
   metadata:
     annotations:
       configmap.reloader.stakater.com/reload: "checkout-config"
       secret.reloader.stakater.com/reload: "checkout-db"
   ```
   Reloader watches and bumps a pod-template annotation, triggering a normal rolling update.

Don't use the immutable + renamed pattern AND Reloader — pick one. The immutable pattern is more common in chart-based deploys (Helm checksums); Reloader is more common in operator-managed CRDs.

## Don't / Do

| Don't | Do |
|---|---|
| Plain `kind: Secret` checked into git | 1Password Operator + Reflector (defer to `flux`), or ESO, or SOPS |
| Stuff a whole config file as a single `ConfigMap` value passed via env var | Mount as a volume |
| `envFrom: configMapRef` and rely on it picking up updates | Files mount, or immutable + rolling deploy |
| Update a live `Secret` and expect running pods to refresh env vars | Restart the pods (Reloader or rollout) |
| Image pull secret on every Pod manually | On the ServiceAccount |
| Long-lived `kubernetes.io/service-account-token` Secret | Bound, audience-scoped `serviceAccountToken` projected volume |
| `binaryData` for non-trivial blobs | Object storage; ConfigMaps cap at 1MiB |
| Reuse one `Secret` across namespaces via copy-paste | Reflector annotations |
| Stock TLS Secret hand-rolled | cert-manager `Certificate` populates a typed `tls` Secret |
| Mount whole `Secret` to get one key | `items:` selector to project just the keys you need |
| Skip `optional: false` on critical secret refs | Explicit `optional: false` — fail fast on missing keys |
