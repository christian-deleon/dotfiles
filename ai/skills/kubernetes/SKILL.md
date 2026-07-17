---
name: kubernetes
description: Modern Kubernetes — manifest authoring, workloads, networking, security, debugging. Use when editing YAML under `manifests/`, `k8s/`, `kustomize/`, or for prompts about kubectl, RKE2, EKS, Deployment/Service/Ingress/HPA/RBAC/NetworkPolicy, Cilium, Traefik, Kyverno, cert-manager. Defers Helm to `helm`, IaC to `terraform`, GitOps to `flux`, inner-loop to `skaffold`. Routes cluster reads via `kubernetes-mcp`.
compatibility: opencode
---

# Kubernetes

Kubernetes is a control loop on top of a distributed object database — every resource is a declared spec the cluster reconciles toward, every controller is a watch-loop that closes the gap between `spec` and `status`. The job isn't writing YAML; it's choosing the right primitive, packaging it correctly, getting it onto the cluster through the right pipeline, and operating it once it's running. The YAML is the cheapest part. The decisions around it are the work.

The most common AI failure mode is producing manifests that lint clean and look modern but skip the parts that matter on day two: missing probes, no `PodDisruptionBudget`, requests-without-limits (or limits-without-requests), `Ingress` with no TLS issuer, `Deployment` with no `topologySpreadConstraints`, mutable image tags in production, default-permit `NetworkPolicy` posture, and `kubectl apply`-by-hand to a cluster that should only be reconciled by GitOps. None of those are syntax errors. All of them bite.

## Decision tree — what to do, where to look

| User wants to… | Read |
|---|---|
| Write a `Deployment`/`StatefulSet`/`DaemonSet`/`Job`/`CronJob` — probes, security context, sidecars, init containers, lifecycle | [workloads.md](workloads.md) |
| Expose a workload — `Service`, Traefik `IngressRoute`, `NetworkPolicy`, DNS, headless services | [networking.md](networking.md) |
| Wire config or secrets into a Pod — `ConfigMap`, `Secret`, projected volumes, immutable configs | [config-secrets.md](config-secrets.md) |
| Persist data — `PVC`, `StorageClass`, CSI driver choice, volume snapshots, StatefulSet templates | [storage.md](storage.md) |
| Lock things down — RBAC, ServiceAccounts, Pod Security Admission, Kyverno, image signing | [security.md](security.md) |
| Right-size and scale — requests/limits, QoS, HPA/KEDA, VPA, PDB, PriorityClass, topology spread, quotas | [resources.md](resources.md) |
| Observability — Grafana LGTM stack (Loki/Grafana/Tempo/Mimir) + Alloy collectors | [observability.md](observability.md) |
| Build, upgrade, drain, or operate a cluster — RKE2, K3s, k3d, kind, version skew, node maintenance | [clusters.md](clusters.md) |
| Debug a broken workload — OOMKilled, ImagePullBackOff, CrashLoopBackOff, Pending pods, networking issues | [debugging.md](debugging.md) |

Manifest skeletons live in [`examples/`](examples/) — copy and edit, don't write from scratch.

## What this skill defers

This is a deliberately narrow skill. Adjacent concerns belong to dedicated skills — extend or fix those rather than duplicating their content here:

| Concern | Defer to |
|---|---|
| Helm chart authoring + consumption (templates, values, lint, package, push, install) | **`helm`** skill |
| GitOps reconciliation (Flux `Kustomization`, `HelmRelease`, sources, 1Password Operator + Reflector secrets) | **`flux`** skill |
| Inner dev loop (file sync, hot reload, port-forward, log tail during dev) | **`skaffold`** skill |
| EKS specifics (Karpenter, Pod Identity, AL Load Balancer Controller, EKS add-ons) | **`aws`** skill → `eks.md` |
| Terraform/OpenTofu — provisioning the cluster, deploying via `helm_release`/`kubernetes_manifest` | **`terraform`** skill |
| Reading live cluster state | **`kubernetes-mcp`** skill (routes through `mcp__kubernetes__*` tools) |

If you find yourself wanting to write Helm template syntax, a `HelmRelease`, a Karpenter `NodePool`, a `terraform { ... }` block, or a `skaffold.yaml` here — stop, switch skills.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Min API surface | **GA only** — `apps/v1`, `networking.k8s.io/v1`, `policy/v1`, `autoscaling/v2`, `gateway.networking.k8s.io/v1`, `rbac.authorization.k8s.io/v1` | No `*v1beta1` in new manifests |
| Min cluster version | **1.30+** | Pod Security Admission stable, sidecar containers GA, in-place pod resize beta |
| Cloud production cluster | **EKS** | Defer to `aws/eks.md` |
| On-prem HA production cluster | **RKE2** | Hardened defaults, containerd, FIPS-capable |
| Single-node production (edge, small services) | **K3s** | Single binary, embedded etcd if HA, Traefik bundled |
| Local dev — Rancher/SUSE-aligned | **k3d** | k3s-in-Docker; matches RKE2/K3s prod |
| Local dev — cloud/EKS-aligned | **kind** | Nodes-in-Docker, conformance-tested, CI parity |
| Provisioning | **Always Terraform/OpenTofu** | Defer to `terraform` skill — cluster create included |
| Packaging | **Helm first.** Author a chart if none exists. Plain manifests only inside a chart or rendered by Terraform | Defer to `helm` skill |
| Inner dev loop | **Skaffold** | Defer to `skaffold` skill — never for prod |
| Production reconciliation | **GitOps via Flux** | Defer to `flux` skill |
| CNI | **Cilium** for new clusters | eBPF, L3-L7 NetworkPolicy, kube-proxy replacement, native Gateway API. RKE2 ships Canal; swap for Cilium at install time. |
| Ingress | **Traefik** | `IngressRoute` CRD primary; `Ingress` v1 acceptable; Traefik also speaks Gateway API |
| Service mesh | **Don't add one** unless L7 features Traefik/Gateway can't give you are needed | Reach for it last; if forced → Istio ambient or Linkerd |
| Cert mgmt | **cert-manager** | `ClusterIssuer` per environment; ACME (Let's Encrypt/ZeroSSL) or PKI |
| Secrets | **1Password Operator + Reflector** | Defer to `flux` skill for details |
| Admission policy | **Kyverno** | Over OPA Gatekeeper for typical work |
| Pod Security | **Pod Security Admission `restricted`** | Exception namespaces are deliberate, labeled, reviewed |
| HPA | **metrics-server** baseline, **KEDA** for event-driven | KEDA for queue depth, Kafka lag, anything non-CPU/mem |
| Autoscaling — EKS | **Karpenter** | Defer to `aws/eks.md` |
| Autoscaling — RKE2 / K3s / others | **Cluster Autoscaler** if supported by the backend; else fixed node pools | |
| Observability | **Grafana LGTM** — Loki + Grafana + Tempo + Mimir (+ Pyroscope for profiling) collected by **Alloy** | See [observability.md](observability.md) |
| Image build | **buildx** (BuildKit) | cosign for signing, syft for SBOM |
| Backup | **Velero** | Snapshot + manifest backup |
| TUI / CLI | **k9s** (configured in this repo), `kubectx`/`kubens` (aliased), `stern` for multi-pod logs | See `~/.dotfiles/functions.d/kubernetes.sh` |

## Universal rules

1. **IaC for provisioning. GitOps for deployment. Period.** `kubectl apply` to a production cluster is a smell. Raw manifests live inside a Helm chart, get rendered by Terraform's `helm_release` / `kubernetes_manifest`, or get reconciled by Flux. The CLI is for **reads and debugging** in prod.
2. **Helm first.** If a maintained upstream chart exists, use it (`helm` skill). If not, author one. Bare `*.yaml` directories are last resort and only acceptable inside a Kustomize overlay being consumed by Flux.
3. **Skaffold is the inner loop, not the outer loop.** It builds + applies during development. Production uses Flux.
4. **Always namespace.** Never `default`. Set `metadata.namespace` explicitly; don't rely on the active context.
5. **Three probes — `startupProbe`, `livenessProbe`, `readinessProbe` — never copied blindly.** Each answers a different question; see [workloads.md](workloads.md).
6. **Requests AND limits on every container.** Memory limits always. CPU limits sometimes (call out the trade-off — see [resources.md](resources.md)).
7. **`runAsNonRoot: true`, `readOnlyRootFilesystem: true`, drop ALL capabilities** unless the workload genuinely needs otherwise. `securityContext` is mandatory, not optional.
8. **Pin images by digest in production manifests** (`image: registry/name@sha256:...`). Not `:latest`, not floating tags. Cosign-verify in admission.
9. **`PodDisruptionBudget` + `topologySpreadConstraints`** on anything with `replicas > 1`. `podAntiAffinity` is a fallback, not a default.
10. **`NetworkPolicy` default-deny per namespace, then allow explicitly.** Requires a CNI that enforces (Cilium does; RKE2's default Canal does; bare Flannel does not).
11. **Pod Security Admission `restricted` at the cluster level.** Workloads that need privileges live in deliberately labeled exception namespaces, reviewed during onboarding.
12. **Cluster state reads via `mcp__kubernetes__*`** (analogous to the `aws-mcp` rule). See [`kubernetes-mcp`](../kubernetes-mcp/SKILL.md).

## Recommended labels

Every resource gets the canonical `app.kubernetes.io/*` label set (this is also what Helm's `_helpers.tpl` produces by default):

```yaml
metadata:
  labels:
    app.kubernetes.io/name: checkout
    app.kubernetes.io/instance: checkout-prod
    app.kubernetes.io/version: "1.4.2"
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: checkout-platform
    app.kubernetes.io/managed-by: Helm     # or 'Flux', or 'Tofu'
```

Selectors only ever match on `app.kubernetes.io/name` + `app.kubernetes.io/instance` (the **immutable** pair). Never select on `version` — you'll break rolling updates.

## kubectl cheat sheet — read-only reflexes

```bash
# Context / namespace (use the dotfiles helpers when interactive)
kc                          # fzf-pick context
kn                          # fzf-pick namespace
kcs                         # fzf-pick kubeconfig file
kpa <pattern>               # all pods excluding system namespaces, grep'd

# Inspect
kubectl get pods -o wide
kubectl describe pod <name>
kubectl get events --sort-by=.lastTimestamp
kubectl get all -n <ns>
kubectl get <kind> <name> -o yaml | yq 'del(.metadata.managedFields, .status)'

# Logs (prefer stern for multi-pod)
kubectl logs <pod> -c <container> --previous --tail=200 -f
stern -n <ns> -l app.kubernetes.io/name=<app>

# Debug a running pod (1.25+ — ephemeral debug container)
kubectl debug -it <pod> --image=busybox:1.36 --target=<container>

# Run a throwaway pod
kubectl run dbg --rm -it --image=nicolaka/netshoot --restart=Never -- bash

# Render before apply (always)
kubectl diff -f manifest.yaml
helm diff upgrade <release> <chart> -n <ns> -f values.yaml      # via helm-diff plugin
```

For state queries in real conversations, prefer `mcp__kubernetes__*` over shelled `kubectl`.

## Minimum-viable manifests

When you genuinely have to write raw YAML (inside a Helm chart's `templates/` or a Kustomize overlay), reach for [`examples/`](examples/):

- `examples/deployment.yaml` — Deployment with probes, resources, securityContext, topologySpread, PDB-compatible
- `examples/statefulset.yaml` — StatefulSet with volumeClaimTemplate + headless Service
- `examples/service.yaml` — ClusterIP + headless + LoadBalancer patterns
- `examples/ingressroute-traefik.yaml` — Traefik `IngressRoute` with TLS via cert-manager
- `examples/networkpolicy.yaml` — default-deny + explicit allow patterns
- `examples/hpa.yaml` — `autoscaling/v2` HPA with scaling behavior tuned
- `examples/cronjob.yaml` — CronJob with concurrency / history defaults set
- `examples/pdb.yaml` — PodDisruptionBudget with `minAvailable`

These are skeletons, not full charts. For chart structure, defer to the `helm` skill.

## Don't / Do

| Don't | Do |
|---|---|
| `kubectl apply -f .` to production | Commit YAML to git; Flux reconciles. CLI for reads only. |
| Write a raw `*.yaml` tree when a chart exists | Use the chart. If none → author one. (Defer to `helm` skill.) |
| `image: myapp:latest` in prod | `image: myapp@sha256:…` (digest pin) |
| `extensions/v1beta1`, `apps/v1beta1`, `networking.k8s.io/v1beta1` | GA versions only |
| `Ingress` for everything | `IngressRoute` (Traefik CRD) for new work; `Ingress` v1 when the chart only ships that |
| Skip probes ("the readiness probe defaults to whatever Kubernetes does") | `startupProbe` + `livenessProbe` + `readinessProbe`, each deliberate |
| Only set `limits` (no requests) | Both. Memory: requests == limits typical. CPU: see [resources.md](resources.md). |
| `replicas: 3` and call it HA | `replicas` + `PodDisruptionBudget` + `topologySpreadConstraints` |
| Default-permit `NetworkPolicy` posture | Default-deny per namespace, then explicit allow |
| `privileged: true`, `runAsUser: 0` | `runAsNonRoot: true`, drop ALL capabilities, read-only root FS |
| Mutate live resources with `kubectl edit` | Edit YAML in git, let Flux reconcile |
| `kubectl scale` as a deploy gate | Update the manifest (or values), let GitOps roll it out |
| `helm install` in prod | `HelmRelease` reconciled by Flux (defer to `flux` skill) |
| Skaffold pointing at prod | Skaffold is dev-only |
| Read cluster state by shelling out to `kubectl` | `mcp__kubernetes__*` tools (`kubernetes-mcp` skill) |
| `kubectl logs <pod>` for a multi-pod service | `stern -n <ns> -l <selector>` |
| Custom roll-your-own metrics pipeline | Grafana LGTM + Alloy ([observability.md](observability.md)) |
| Suspend Flux as a deploy lever | Revert the commit; suspend hides drift |

## Adding to this skill

When a new convention lands, add it to the relevant topic file (or create a new one and link it from the decision tree). Keep `SKILL.md` lean — the decision tree is the contract, depth lives in topic files.
