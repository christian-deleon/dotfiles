# Security

Kubernetes security is layered. From "the container can't do anything" out to "the user can't do anything they shouldn't":

| Layer | Mechanism |
|---|---|
| Process inside container | `securityContext` (non-root, dropped caps, read-only FS, seccomp) |
| Container runtime | Pod Security Admission, AppArmor, seccomp |
| Pod → API server | `ServiceAccount` + RBAC |
| Pod → other pods | `NetworkPolicy` (see [networking.md](networking.md)) |
| Cluster admission | Kyverno (or OPA Gatekeeper) policies |
| Image provenance | cosign signatures + Kyverno verifyImages |
| User → API server | OIDC, IAM (cloud-managed), `kubectl` configs |
| etcd at rest | KMS encryption (cluster-install concern) |

Each layer is independent. Missing one means the others have to compensate. This file covers everything except `NetworkPolicy`.

## ServiceAccounts and pod identity

Every pod runs as a `ServiceAccount`. By default it's the namespace's `default` SA — that's the wrong identity for almost everything.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: checkout
  namespace: checkout
automountServiceAccountToken: false                            # see below
imagePullSecrets:
  - name: ghcr-pull
```

```yaml
# In the PodSpec
spec:
  serviceAccountName: checkout
  automountServiceAccountToken: false                          # opt-in if the pod actually needs API access
```

Rules:

- **One SA per workload.** Not "one SA per namespace." The pod's identity is its blast radius — keep it scoped.
- **`automountServiceAccountToken: false` by default.** Most pods don't talk to the API server. The default token is a credential they didn't ask for.
- **Bound tokens (1.24+) replace long-lived SA Secrets.** The token in `/var/run/secrets/kubernetes.io/serviceaccount/token` is now audience-scoped, time-bound, and auto-rotated. The legacy `kubernetes.io/service-account-token` Secret pattern is dead — don't generate one unless you have a tool that can't handle bound tokens.

### Cloud IAM for pod identity

Pods that need cloud-provider APIs (S3, GCS, Secrets Manager) should use the cloud's pod-identity bridge, not long-lived access keys mounted as Secrets:

- **EKS** — Pod Identity (preferred for new work) or IRSA. Defer to `aws/eks.md`.
- **GKE** — Workload Identity Federation.
- **AKS** — Workload Identity (replaces the deprecated pod-managed identity).
- **On-prem** — issue mTLS certs via SPIRE / SPIFFE, or use Vault's Kubernetes auth backend.

The shape is consistent: annotate the SA → cloud IAM trusts the bound token in lieu of credentials → pod gets temporary creds via the SDK chain. No static keys.

## RBAC

Four primitives:

| Kind | Scope |
|---|---|
| `Role` | Namespace-scoped permissions |
| `RoleBinding` | Grants a `Role` (or `ClusterRole`) to a subject **in one namespace** |
| `ClusterRole` | Cluster-scoped permissions, or a reusable template |
| `ClusterRoleBinding` | Grants a `ClusterRole` to a subject **cluster-wide** |

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: checkout-reader, namespace: checkout }
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    resourceNames: ["checkout-config", "checkout-db"]
    verbs: ["get", "watch", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: checkout-reader, namespace: checkout }
subjects:
  - kind: ServiceAccount
    name: checkout
    namespace: checkout
roleRef:
  kind: Role
  name: checkout-reader
  apiGroup: rbac.authorization.k8s.io
```

Rules:

- **Smallest viable verb set.** `get`/`list`/`watch` for read access. `create`/`update`/`patch`/`delete` only when actually needed. Never `*`.
- **`resourceNames:` for single-resource access.** If a pod only needs to read one ConfigMap, name it. The kubelet enforces this efficiently.
- **`Role` + `RoleBinding` in the same namespace.** Cross-namespace access via `ClusterRole` + `RoleBinding`-in-the-consumer-namespace.
- **Never grant `cluster-admin`** to a workload SA. If something seems to need it, you're missing a Role.
- **Aggregated `ClusterRole`s** (`aggregationRule`) let multiple operators contribute permissions to a single role — preferred over hand-maintained super-roles.

### The four built-in ClusterRoles

| Role | Use |
|---|---|
| `cluster-admin` | Cluster-wide superuser. Bind only to cluster operators, never to workloads. |
| `admin` | Namespace-wide superuser. For team leads' RBAC in their namespace. |
| `edit` | CRUD on common resources, no RBAC/Quota. For developers. |
| `view` | Read-only on common resources, **excludes Secrets**. For broader access. |

These are starting points, not endpoints. Most production setups define narrower custom roles.

### Auditing what an SA can do

```bash
kubectl auth can-i --as=system:serviceaccount:checkout:checkout get secrets -n checkout
kubectl auth can-i --list --as=system:serviceaccount:checkout:checkout -n checkout
```

Use this before granting permissions ("does it already have this?") and after ("did I grant too much?").

## Pod Security Admission (PSA)

PSA enforces three baselines at admission time, labeled per namespace:

| Level | What it bans |
|---|---|
| `privileged` | Nothing — anything goes |
| `baseline` | Privileged pods, hostPath, hostNetwork, host PID/IPC, capabilities not in the default set |
| `restricted` | Above + non-root required, dropped ALL caps, `seccompProfile: RuntimeDefault`, no privilege escalation, read-only root FS |

Label namespaces (three modes per level — `enforce`, `audit`, `warn`):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: checkout
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

Cluster-level policy is to enforce `restricted` everywhere, with deliberate exception namespaces for system components that genuinely need privileges (e.g. `kube-system`, `cilium-system`, the CSI driver namespace). Mark each exception explicitly and review at onboarding.

Workload `securityContext` for `restricted` compliance:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    fsGroup: 65532
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: [ALL] }
        runAsNonRoot: true
```

This is the minimum every new workload should ship with. See [workloads.md](workloads.md) for the full PodSpec.

## seccomp and AppArmor

`seccompProfile: RuntimeDefault` is the kubelet's default profile, which blocks a sane set of dangerous syscalls. Set it explicitly:

```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault                                       # or 'Localhost' with a localhostProfile
```

`Localhost` lets you ship a custom profile (e.g. a hardened one generated by tracing the app's syscalls with `bane` or `oci-seccomp-bpf-hook`). Worth doing for high-value workloads, not by default for everything.

AppArmor (1.30+ GA via `securityContext`):

```yaml
spec:
  containers:
    - name: app
      securityContext:
        appArmorProfile:
          type: RuntimeDefault                                 # or 'Localhost' + localhostProfile
```

Only available on AppArmor-enabled distros (Ubuntu, Debian, openSUSE — RKE2 enables it). Cluster-level setup is in [clusters.md](clusters.md).

## Admission control with Kyverno

Kyverno is the YAML-native policy engine. Prefer it over OPA Gatekeeper for new work — policies are first-class Kubernetes resources, not Rego.

Three kinds of policies:

```yaml
# 1. Validate — reject manifests that violate a rule
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-runasnonroot }
spec:
  validationFailureAction: Enforce                             # Enforce (block) | Audit (warn only)
  rules:
    - name: containers-must-runasnonroot
      match:
        any:
          - resources: { kinds: [Pod] }
      validate:
        message: "runAsNonRoot must be true."
        pattern:
          spec:
            =(securityContext):
              =(runAsNonRoot): true
            containers:
              - =(securityContext):
                  =(runAsNonRoot): true
```

```yaml
# 2. Mutate — modify manifests at admission
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: add-default-network-policy }
spec:
  rules:
    - name: add-defaultdeny
      match: { any: [{ resources: { kinds: [Namespace] } }] }
      generate:                                                # generate child resources on parent create
        kind: NetworkPolicy
        apiVersion: networking.k8s.io/v1
        name: default-deny
        namespace: "{{request.object.metadata.name}}"
        synchronize: true
        data:
          spec:
            podSelector: {}
            policyTypes: [Ingress, Egress]
```

```yaml
# 3. VerifyImages — enforce cosign signatures and SBOM attestations at admission
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: verify-image-signatures }
spec:
  webhookTimeoutSeconds: 30
  rules:
    - name: check-signature
      match: { any: [{ resources: { kinds: [Pod] } }] }
      verifyImages:
        - imageReferences: ["ghcr.io/example/*"]
          attestors:
            - count: 1
              entries:
                - keyless:
                    subject: "https://github.com/example/*/.github/workflows/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor: { url: "https://rekor.sigstore.dev" }
```

Cluster baseline policy pack (defaults to recommend everywhere):

- Require resources requests + limits (with [resources.md](resources.md) caveats for CPU limits)
- Require `runAsNonRoot: true` + `readOnlyRootFilesystem: true` + dropped caps
- Disallow `latest` and unpinned image tags in production namespaces
- Require image signature verification on production namespaces
- Disallow `hostPath`, `hostNetwork`, `hostPID`, `hostIPC` outside system namespaces
- Generate a default-deny `NetworkPolicy` on namespace create
- Require `app.kubernetes.io/name` + `app.kubernetes.io/instance` labels

Kyverno's [Pod Security policy pack](https://kyverno.io/policies/pod-security/) is a strong starting point — install it, then layer org-specific policies on top.

### Audit before Enforce

When introducing a new policy on a populated cluster:

1. Ship it with `validationFailureAction: Audit` first.
2. Watch `PolicyReport` resources to find existing violations.
3. Fix the violations.
4. Flip to `Enforce`.

`Audit` -> `Enforce` is a common rollout pattern. Skipping the audit phase causes immediate prod incidents on any pre-existing violation.

## Image signing — cosign + sigstore

Sigstore's cosign is the default for OCI image signing. Two modes:

- **Keyless** (preferred for CI): the signing key is ephemeral, identity is asserted via OIDC (GitHub Actions, GCP, etc.) and a Rekor transparency log entry. No keys to rotate or leak.
- **Keyed**: cosign-managed key in a KMS (AWS KMS, GCP KMS, Vault). Use only if you need to sign offline or have a regulatory reason.

In CI, after build/push:

```bash
cosign sign --yes ghcr.io/example/checkout@sha256:<digest>
cosign attest --yes --predicate sbom.spdx.json --type spdxjson ghcr.io/example/checkout@sha256:<digest>
```

Verify at admission via Kyverno (above) or `cosign verify` in pre-deploy CI. **Don't** rely on cluster-side verification alone — sign in CI, verify at every boundary (registry replication, deploy admission, runtime).

## Supply-chain extras worth knowing

| Tool | What it does |
|---|---|
| **syft** | Generates SBOMs (SPDX or CycloneDX) from images |
| **grype** | Scans images / SBOMs for known vulns |
| **trivy** | Image / config / IaC scanning (also handy for Helm chart scans) |
| **cosign attest** | Attaches SBOM + provenance as signed attestations alongside the image |
| **SLSA provenance** | Build-system attestation (GitHub Actions emits this natively for Sigstore) |
| **kube-bench** | CIS Kubernetes benchmark against a running cluster |
| **kubescape** | Cluster posture scan, NSA/CISA hardening guide checks |

A reasonable baseline: SBOM (syft) → grype/trivy scan → cosign sign + attest in CI → Kyverno `verifyImages` at admission → kube-bench in cluster CI.

## Audit logging

The API server emits an audit log when configured at install time (`--audit-log-path`, `--audit-policy-file`). What to log:

- **`Metadata` level for everything** — who did what, when.
- **`Request` level for Secret/ConfigMap operations** — captures the request body (but **not** the response).
- **`RequestResponse` level for the policy-violation classes** that need forensic detail.

Ship the audit log to your log backend (Loki via Alloy; see [observability.md](observability.md)). Cluster-install concern; defer details to [clusters.md](clusters.md).

## etcd encryption

By default, `Secret` data in etcd is base64-encoded, not encrypted. Cluster admins should configure an `EncryptionConfiguration` with a KMS provider:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: ["secrets"]
    providers:
      - kms:
          name: aws-kms                                        # or gcp-kms, vault, etc.
          endpoint: unix:///var/run/kmsplugin/socket.sock
          cachesize: 1000
      - identity: {}                                          # fallback for already-stored data
```

Without this, a node-disk compromise reveals every Secret. This is a cluster-install concern; ask the cluster owner if you're unsure whether it's enabled.

## Don't / Do

| Don't | Do |
|---|---|
| Pods running as `default` SA | One SA per workload, `automountServiceAccountToken: false` unless needed |
| `cluster-admin` on a workload | Narrow `Role` + `RoleBinding` |
| `verbs: ["*"]` or `resources: ["*"]` | Smallest viable verb/resource set |
| Long-lived SA token Secret | Bound, audience-scoped tokens (1.24+ default) |
| Static cloud access keys in Secrets | Pod Identity / Workload Identity / SPIRE |
| Namespace without `pod-security.kubernetes.io/enforce` | Label every namespace; `restricted` is the cluster default |
| `runAsRoot` or unset `runAsNonRoot` | `runAsNonRoot: true`, explicit non-zero `runAsUser`/`runAsGroup` |
| `readOnlyRootFilesystem: false` | `true`; mount `emptyDir` for `/tmp` and any writable path |
| `capabilities.add: [NET_ADMIN, ...]` casually | Drop ALL, add back only specific capabilities, document why |
| `privileged: true` without an exception namespace | Move to a labeled exception namespace; reviewed at onboarding |
| OPA Gatekeeper for new work | Kyverno (YAML-native, easier audit/enforce flow) |
| Roll policies straight to `Enforce` | Ship `Audit` first, fix violations, then `Enforce` |
| Unsigned production images | cosign keyless sign in CI, Kyverno `verifyImages` at admission |
| Skip SBOM | syft in CI; cosign attest the result |
| Trust the cluster's default audit config | Define explicit `Policy` resources; ship to Loki |
| Assume etcd is encrypted | Confirm `EncryptionConfiguration` with a KMS provider is configured |
