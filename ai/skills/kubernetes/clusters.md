# Clusters — Choosing, Building, Operating

A cluster is a control plane + a data plane + a CNI + a handful of cluster-scoped add-ons. Pick the distribution by **where it runs** and **what guarantees you need on day two**:

| Use case | Distribution |
|---|---|
| Cloud production | **EKS** — defer to `aws/eks.md` |
| On-prem HA production | **RKE2** |
| Single-node production (edge, lab, small services) | **K3s** |
| Local dev — Rancher/SUSE-aligned | **k3d** (k3s-in-Docker) |
| Local dev — cloud/EKS-aligned | **kind** |

Everything else (kubeadm, microk8s, k0s, OpenShift, vanilla upstream) is either legacy, a different layer (OpenShift is a PaaS, not a distro), or covered by one of the above.

This file does **not** cover EKS specifics — those live in `aws/eks.md`. Helm chart authoring lives in the `helm` skill. GitOps reconciliation lives in the `flux` skill.

## RKE2 — on-prem HA production

RKE2 is Rancher's hardened distribution. It runs `containerd`, applies CIS-benchmark defaults, supports SELinux + FIPS, and is fully Kubernetes-conformant. Single-node, multi-server (HA), and mixed configurations are all in scope.

### When to choose RKE2

- You need conformance-tested, hardened Kubernetes on your own hardware.
- You want a Cluster API conformant control plane without operating it from scratch.
- You're on-prem and want a vendor-neutral path forward (no AWS / GCP lock-in).
- You have an air-gapped requirement (RKE2 supports air-gap installs).

### Architecture defaults

| Component | RKE2 default | Override when |
|---|---|---|
| CNI | Canal (Calico + Flannel) | **Swap for Cilium** at install (`--cni=cilium` or via `/etc/rancher/rke2/config.yaml`) |
| Ingress | NGINX (`rke2-ingress-nginx`) | **Disable, install Traefik** via Helm. Add `disable: [rke2-ingress-nginx]` |
| Storage | None (bring your own) | Install Longhorn for replicated block storage |
| etcd | Embedded (3+ servers for HA) | External etcd only if you have a separate etcd ops story |
| Container runtime | containerd | Don't switch |
| Network policy | NetworkPolicy via Canal (works), enforce via Cilium if swapped | Cilium for L7 |

### Minimum HA install

Three server nodes (control plane + etcd) plus N agent nodes (worker-only). Server nodes can also run workloads — `nodeSelector` and taints control placement.

```yaml
# /etc/rancher/rke2/config.yaml — first server
token: <random-shared-secret>
cni: cilium
disable:
  - rke2-ingress-nginx                                         # using Traefik
node-taint:
  - "node-role.kubernetes.io/control-plane=true:NoSchedule"    # if not running workloads on servers
tls-san:
  - cluster.example.internal                                   # add a stable DNS name for the API
write-kubeconfig-mode: "0600"
```

```yaml
# /etc/rancher/rke2/config.yaml — subsequent servers
token: <same-as-above>
server: https://cluster.example.internal:9345
cni: cilium
disable: [rke2-ingress-nginx]
```

```yaml
# /etc/rancher/rke2/config.yaml — agents
token: <same-as-above>
server: https://cluster.example.internal:9345
```

Provision via Terraform (`rke2_*` providers, or vanilla `null_resource` + cloud-init) — defer to the `terraform` skill. **Don't** install RKE2 by hand on real infrastructure.

### Operating RKE2

```bash
# Server-side
systemctl status rke2-server
journalctl -u rke2-server -f
/var/lib/rancher/rke2/bin/kubectl get nodes

# Cluster-wide
sudo cat /var/lib/rancher/rke2/server/cred/admin.kubeconfig | tee ~/.kube/rke2-prod
```

Upgrade RKE2 by changing the version in `/etc/rancher/rke2/config.yaml` (or via `system-upgrade-controller` if installed) and restarting `rke2-server`/`rke2-agent`. Always:

1. Upgrade one server at a time, wait for it to rejoin etcd quorum.
2. Then upgrade agents one at a time, drain before each.
3. Verify add-on compatibility for the new Kubernetes version (Cilium, Longhorn, cert-manager all have version skew matrices — check them).

## K3s — single-node production, edge

K3s is "Kubernetes without the parts you don't need on a single node." Single binary, embedded SQLite (single-server) or embedded etcd (HA), `containerd`, Traefik bundled by default — which **happens to align with the user's Traefik preference**, so it's the rare case where the default is the right default.

### When to choose K3s

- Single-node production where the cost (and ops surface) of RKE2 isn't justified.
- Edge / IoT / branch-office workloads.
- "I want real Kubernetes, not Docker Compose, but I have one node."

### Defaults to be aware of

| Component | K3s default | Notes |
|---|---|---|
| CNI | Flannel | Replace with Cilium for serious network policy (`--flannel-backend=none` + Cilium install) |
| Ingress | Traefik (bundled) | Aligns with the user's preference. Disable with `--disable=traefik` to install a different version yourself. |
| Storage | `local-path` provisioner | Node-local hostpath. Dev OK; production accept node-loss == data-loss, or install Longhorn. |
| Service LB | Klipper (`servicelb`) | Bind-to-host LoadBalancer. Acceptable for single-node. Disable + install MetalLB for multi-node. |
| Datastore | SQLite (single-server) or embedded etcd (HA mode) | Embedded etcd for HA — 3 servers minimum |
| Container runtime | containerd | |

### Install (single-node)

```bash
curl -sfL https://get.k3s.io | sh -                            # installs as systemd service
sudo cat /etc/rancher/k3s/k3s.yaml | tee ~/.kube/k3s-prod
sed -i 's/127.0.0.1/<reachable-ip>/' ~/.kube/k3s-prod
```

Customize via `/etc/rancher/k3s/config.yaml` **before** install:

```yaml
write-kubeconfig-mode: "0600"
disable:
  - servicelb                                                  # using MetalLB
flannel-backend: "none"                                        # using Cilium
disable-network-policy: true                                   # Cilium enforces
cluster-init: true                                             # for HA (first server only)
tls-san:
  - cluster.example.internal
```

### HA K3s

Three servers minimum (embedded etcd):

```bash
# First server
INSTALL_K3S_VERSION=v1.31.* sh -s - server --cluster-init <flags>

# Additional servers
INSTALL_K3S_VERSION=v1.31.* sh -s - server --server https://<first-server>:6443 --token <shared> <flags>
```

For real HA, prefer **RKE2 over HA K3s** — RKE2 is hardened and has better operational tooling. HA K3s exists for the small footprint case; if you can afford RKE2's overhead, take it.

## k3d — local dev, Rancher-aligned

k3d runs K3s in Docker. Each k3d "cluster" is one or more containers, each running a K3s agent or server. Aligns with the K3s/RKE2 production track — what works in k3d generally works in K3s production.

```bash
k3d cluster create dev \
  --servers 1 \
  --agents 2 \
  --image rancher/k3s:v1.31.4-k3s1 \
  --k3s-arg "--disable=traefik@server:0" \
  --port "443:443@loadbalancer" \
  --port "80:80@loadbalancer" \
  --registry-create dev-registry:0.0.0.0:5000
```

Install Traefik yourself afterward so your dev environment matches prod chart version.

## kind — local dev, cloud-aligned

kind runs nodes-in-Docker using vanilla upstream Kubernetes. Conformance-tested by the SIG-Cluster-Lifecycle team. The right choice when you want **local parity with EKS/GKE/AKS** — same upstream, same upgrade cadence.

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true                                      # install Cilium to match prod
  kubeProxyMode: none
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
      - containerPort: 443
        hostPort: 443
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
  - role: worker
  - role: worker
```

```bash
kind create cluster --config kind-config.yaml --name dev --image kindest/node:v1.31.0
helm install cilium cilium/cilium -n kube-system --version 1.16.*
helm install traefik traefik/traefik -n traefik --create-namespace
```

kind is heavier than k3d (full kubelet per node), slower to start, but closer to vanilla upstream. Use kind when you need to test things that depend on upstream kubelet behavior, conformance test, or want to match what EKS gives you.

## Version policy — skew, support, upgrade

Kubernetes releases ~3 minor versions per year (1.X for X in {30, 31, 32, ...}). Each version is supported for **14 months** upstream. Cloud providers add their own support windows.

| Rule | Rationale |
|---|---|
| Stay on **N or N-1** of current GA | Never N-2 — you hit the support cliff while planning the upgrade |
| **Upgrade quarterly** at minimum | Skipping versions isn't supported; each upgrade is sequential |
| **Control plane upgrades before nodes** — never the reverse | The skew window allows control-plane > kubelet by 1 minor, never the reverse |
| **Test in dev before prod** | Always. The cluster-fleet upgrade order is: dev → staging → prod |

Kubernetes version skew rules (1.31+):

| Component | Allowed skew vs control plane |
|---|---|
| kubelet | -3 minor versions (e.g. cluster 1.31, kubelets can be 1.28-1.31) |
| kube-proxy | -3 minor versions |
| kubectl | ±1 minor version |
| Add-ons (Cilium, cert-manager, Traefik, etc.) | Each has its own matrix — **always check before upgrading** |

## Upgrading — the playbook

### Pre-upgrade checklist

1. **Read the changelog and "Urgent Upgrade Notes."** Removed APIs are real and will break manifests.
2. **Run `kubectl deprecations` or `pluto`** to find deprecated API usage. Fix before upgrading.
3. **Pin add-on versions** known compatible with the target K8s version. Confirm via each project's skew matrix.
4. **Snapshot etcd**:
   ```bash
   ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-pre-upgrade.db
   ```
   (RKE2 has built-in snapshots: `rke2 etcd-snapshot save`.) For EKS, the control plane is managed; this isn't your job.
5. **Confirm PDBs are sane** — workloads will be drained during the upgrade. Wrong PDB == stuck drain.
6. **Run the upgrade in dev first**, run the full app test suite against it, then production.

### Order of operations

1. **Control plane** — upgrade one server at a time (RKE2/K3s); cloud-managed clusters trigger via API.
2. **Add-ons** — Cilium, CSI drivers, ingress controllers. Some require Kubernetes version >= X.
3. **Nodes / kubelets** — one at a time, cordon + drain before, uncordon after. Verify pods reschedule cleanly.

### Node drain

```bash
kubectl cordon <node>                                          # no new pods
kubectl drain <node> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=10m
# do the upgrade (reimage, package upgrade, etc.)
kubectl uncordon <node>
```

If drain hangs:

- **PDB blocking**: a workload has `minAvailable` that can't be satisfied if the pod evicts. Fix the PDB or scale up before draining.
- **Pod has finalizers**: check `kubectl get pod <name> -o yaml | yq '.metadata.finalizers'`.
- **Stuck `Terminating` pod**: usually a volume that can't detach. See [debugging.md](debugging.md).

For multi-node clusters, **system-upgrade-controller** (RKE2/K3s) or Karpenter (EKS) automate the cordon→drain→reimage→uncordon dance via `Plan` CRDs.

## CNI choice — Cilium vs everything else

| CNI | Use for |
|---|---|
| **Cilium** | Default for new work — eBPF, NetworkPolicy + L7, kube-proxy replacement, Hubble for flow visibility, Gateway API native |
| Calico | Mature, used by RKE2's default (Canal). Acceptable but switch to Cilium for new work. |
| Flannel | Encap-only, no NetworkPolicy. K3s default. Replace if you care about policy. |
| Weave | Deprecated. Don't. |
| Cloud VPC CNI | EKS uses VPC CNI (pods get VPC IPs). Defer to `aws/eks.md`. |

Cilium installation is consistent across distributions:

```bash
helm install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.16.* \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<api-server-ip> \
  --set k8sServicePort=6443 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set gatewayAPI.enabled=true
```

(Defer chart specifics to the `helm` skill.)

## kubeconfig hygiene

This dotfiles repo's `functions.d/kubernetes.sh` already provides:

| Function | What it does |
|---|---|
| `kcs [name]` | Set `KUBECONFIG` to `~/.kube/<name>`; fzf picker if no arg |
| `kc [name]` | Switch context within current kubeconfig; fzf picker |
| `kn [ns]` | Set default namespace for current context; fzf picker |
| `kca` | Aggregate all `~/.kube/*` files into a single `KUBECONFIG` |
| `kcu` | Unset `KUBECONFIG` (revert to `~/.kube/config`) |

Conventions:

- **One file per cluster** in `~/.kube/`, named `<env>-<cluster>` (e.g. `prod-east`, `staging-rke2`).
- **Never share kubeconfigs across machines** — they contain credentials.
- **Cloud kubeconfigs are short-lived** — refresh via `aws eks update-kubeconfig`, `gcloud container clusters get-credentials`, etc.

## Operator toolkit

Tools beyond `kubectl` worth installing on the operator's machine:

| Tool | Why |
|---|---|
| **k9s** | TUI for browsing clusters; already configured in this repo |
| **kubectx / kubens** | Fast context/namespace switch — already aliased as `kc`/`kn` |
| **stern** | Multi-pod log tail — `stern -n <ns> -l app=foo` |
| **helm** | Chart consumption; defer authoring to the `helm` skill |
| **kustomize** | Standalone; usually invoked via `kubectl kustomize` |
| **pluto / kubectl-deprecations** | Find deprecated API usage |
| **kube-no-trouble (`kubent`)** | Same idea as pluto, different code path |
| **velero** | Cluster backup CLI |
| **cilium / hubble** | When running Cilium — `hubble observe` is invaluable for network debugging |
| **flux** | When running Flux — defer to the `flux` skill |
| **kubectl-tree** | Show owner-reference trees (Pod → ReplicaSet → Deployment → ...) |
| **kubectl-neat** | Strip ManagedFields and noise from `-o yaml` output |

## Multi-cluster strategy

When you have more than one cluster, three approaches:

| Approach | Tools | When |
|---|---|---|
| **Fleet management** (config sync to N clusters) | Flux + per-cluster Kustomize overlays (default — defer to `flux` skill); Rancher Fleet for RKE2/K3s fleets | Most cases |
| **Cluster API** (Kubernetes as a control plane for Kubernetes) | CAPI + cloud provider | When you're spinning many clusters dynamically |
| **Service-mesh-spanning** (multi-cluster service discovery) | Istio multi-cluster, Cilium ClusterMesh, Linkerd multicluster | When workloads need to call across clusters as if it were one |

Don't reach for multi-cluster until you can name the specific failure mode you're trying to solve. "Resilience" is usually solved by multi-AZ within one cluster, not multiple clusters.

## Don't / Do

| Don't | Do |
|---|---|
| `kubeadm` for new work | RKE2 (on-prem) or managed (cloud) |
| K3s in HA when RKE2 would do | RKE2 for serious HA; K3s for single-node or edge |
| Run K3s with default Flannel + assume NetworkPolicy works | Replace with Cilium |
| Mix kind and k3d in one project without reason | Pick one based on prod target |
| `--all-namespaces` upgrades — upgrade the whole cluster in one shot | One node at a time, with cordon+drain |
| Skip etcd snapshot before upgrades | Always snapshot (RKE2: built-in; vanilla: `etcdctl snapshot save`) |
| Upgrade kubelet before control plane | Control plane first; kubelet can lag by up to 3 minors |
| Hot-patch CNI at runtime | Swap CNI at install only — or carefully via documented migration |
| Multi-cluster because "it sounds robust" | Single multi-AZ cluster first; multi-cluster when you can name the specific failure mode |
| Hand-roll cluster install on real infra | Provision via Terraform (defer to `terraform` skill) |
| One mega-kubeconfig with every cluster merged | One file per cluster in `~/.kube/`, use `kcs`/`kc` to switch |
