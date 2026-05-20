# EKS

EKS is managed Kubernetes — the control plane is AWS's problem, the data plane is yours. The mental model: **a cluster is a control plane + add-ons + one or more node pools + an IAM identity bridge from pods to AWS services**. The right default in 2026 is **a current EKS version, Karpenter for node autoscaling, Pod Identity (not IRSA) for pod-level IAM, the AWS-managed core add-ons via the `Addon` API, and Flux for application reconciliation**.

The most common AI failure mode: cluster pinned to an EKS version two releases behind, manual managed-node-groups instead of Karpenter, IRSA being added for new work when Pod Identity is now the better default, AWS Load Balancer Controller missing or installed by hand, and CoreDNS / VPC CNI add-ons left at whatever the cluster bootstrapped with.

This skill is the AWS-side conventions for EKS. Defer to:

- **`terraform`** for HCL mechanics (provider, modules, state).
- **`flux`** for GitOps reconciliation (`HelmRelease`, `Kustomization`, `GitRepository`).
- **`helm`** for chart authoring/consumption (`Chart.yaml`, `values.yaml`, templating, OCI distribution).
- **`skaffold`** for the inner-loop dev workflow against the cluster (build, sync, port-forward, debug).

## Defaults

| Concern | Default |
|---|---|
| Version | **Latest stable supported by Karpenter / Flux** — typically N-1 from EKS GA |
| Control plane | AWS-managed (always) — `aws_eks_cluster` |
| Compute | **Karpenter** for autoscaling. Managed node groups only for system workloads or where Karpenter isn't viable |
| Architecture | **`arm64` (Graviton)** nodes by default |
| AMI | **Bottlerocket** for new clusters; AL2023 acceptable. AL2 is EOL — never for new work |
| Pod IAM | **EKS Pod Identity** for new clusters/workloads. IRSA remains valid for existing — see migration notes |
| CNI | **VPC CNI** with prefix delegation enabled (pod density) |
| Ingress | **AWS Load Balancer Controller** + Ingress / Gateway API |
| Secrets | **External Secrets Operator** OR **1Password Operator + Reflector** (see `flux` skill) |
| Observability | CloudWatch Container Insights + AMP / AMG if Prometheus stack |
| Reconciliation | **Flux v2** — see `flux` skill |

## Version policy

EKS supports each version for **14 months of standard + 12 months of extended** (paid). Two rules:

- **Stay on N or N-1 from current GA.** Never N-2 — you'll hit the support cliff while planning the upgrade.
- **Upgrade quarterly** at minimum. Skipping versions isn't allowed; each upgrade is sequential.

Pin the version explicitly:

```hcl
resource "aws_eks_cluster" "this" {
  name    = "prod-platform"
  version = "1.32"   # explicit, never "latest"
  # ...
}
```

Upgrade order (always):

1. Control plane (`aws_eks_cluster.version`).
2. Add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI, Pod Identity Agent) — bump to versions compatible with the new K8s.
3. Node groups — Karpenter rolls automatically once AMI version updates; managed groups need manual `aws_eks_node_group.version` bump.

## Cluster shape

Single cluster per `(env, region)` is the default. Per-team clusters are rarely worth the multi-tenancy savings unless you have a dozen+ teams.

```hcl
resource "aws_eks_cluster" "this" {
  name     = "prod-platform"
  role_arn = aws_iam_role.cluster.arn
  version  = "1.32"

  access_config {
    authentication_mode                         = "API"   # not API_AND_CONFIG_MAP
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["203.0.113.0/24"]    # office CIDR or empty
  }

  upgrade_policy {
    support_type = "STANDARD"   # avoid drifting into EXTENDED
  }

  enabled_cluster_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }
}
```

Required toggles:

- **`authentication_mode = "API"`** — the modern access-entry path, replaces `aws-auth` ConfigMap. Don't use `API_AND_CONFIG_MAP` for new clusters.
- **`bootstrap_cluster_creator_admin_permissions = false`** — don't grant admin to whoever ran `terraform apply`. Use explicit access entries.
- **`enabled_cluster_log_types`** — turn on at least `audit` and `authenticator`. Without `audit`, breach forensics is much harder.
- **`encryption_config` for `secrets`** — envelope encryption of K8s Secrets with KMS.

### Endpoint exposure

Default: **private + public, public CIDR-restricted** to a known set (office, VPN). Fully private (`endpoint_public_access = false`) only if there's a Direct Connect/VPN path and you have an alternative `kubectl` access mechanism (SSM tunnel, jumphost in-VPC).

## Access — access entries, not `aws-auth`

The old `aws-auth` ConfigMap pattern is deprecated. Use **access entries**:

```hcl
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.eks_admin.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.eks_admin.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
```

Common policies:

| Policy | Scope |
|---|---|
| `AmazonEKSClusterAdminPolicy` | cluster-wide admin |
| `AmazonEKSAdminPolicy` | namespace admin |
| `AmazonEKSEditPolicy` | namespace edit |
| `AmazonEKSViewPolicy` | namespace view |

Map IAM Identity Center permission sets to access entries, not individual IAM users.

## Compute — Karpenter is the default

EKS has three compute options. Pick by use case, not by familiarity:

| Option | Use |
|---|---|
| **Karpenter** | **Default.** Autoscaling, multi-AZ, spot-first, instance-type diversity, fast |
| **Managed Node Groups** | System workloads pre-Karpenter (Karpenter, CoreDNS) — boot the cluster |
| **Fargate** | Per-pod billing, no node management. Limits: no DaemonSets, no GPU, no privileged. Niche. |

The canonical pattern:

- **One managed node group** with 2–3 small Graviton instances for system pods (Karpenter itself, CoreDNS, AWS LB Controller). Taints + tolerations keep app workloads off it.
- **Karpenter** for everything else, configured with `NodePool` + `EC2NodeClass` to span Graviton instance families across all AZs, spot-first with on-demand fallback.

Minimal Karpenter `NodePool`:

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["m7g", "c7g", "r7g", "m7gd"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
```

Notes:

- **`spot` first, `on-demand` second** — Karpenter picks the cheapest available.
- **Multiple instance families** — diversification reduces spot interruption rate.
- **`consolidateAfter: 30s`** — aggressive bin-packing; safe because Pod Disruption Budgets gate eviction.

## Pod Identity vs IRSA

**EKS Pod Identity** (launched 2023) is the new default for granting AWS IAM to pods. It replaces **IRSA** (IAM Roles for Service Accounts) for new workloads.

| | IRSA | Pod Identity |
|---|---|---|
| Setup | OIDC provider per cluster, role trust policy per role | One `eks-pod-identity-agent` add-on, one association per workload |
| Trust policy | Cluster-OIDC-scoped, regex on SA path | No trust policy needed — IAM API handles it |
| Cross-account | Awkward (manual trust) | Native via association |
| Role reuse | One role per cluster (OIDC tied to cluster) | One role works across clusters |

For new clusters and new workloads: **Pod Identity**.
For existing IRSA-based workloads: **keep them**, migrate opportunistically.

### Pod Identity setup

1. Install the add-on:

   ```hcl
   resource "aws_eks_addon" "pod_identity" {
     cluster_name = aws_eks_cluster.this.name
     addon_name   = "eks-pod-identity-agent"
   }
   ```

2. Create the IAM role with a Pod Identity trust policy:

   ```hcl
   data "aws_iam_policy_document" "pod_assume" {
     statement {
       actions = ["sts:AssumeRole", "sts:TagSession"]
       principals {
         type        = "Service"
         identifiers = ["pods.eks.amazonaws.com"]
       }
     }
   }
   ```

3. Associate the role with a Kubernetes ServiceAccount:

   ```hcl
   resource "aws_eks_pod_identity_association" "checkout" {
     cluster_name    = aws_eks_cluster.this.name
     namespace       = "checkout"
     service_account = "checkout-api"
     role_arn        = aws_iam_role.checkout_pod.arn
   }
   ```

The pod uses the SA `checkout/checkout-api`; the agent injects credentials transparently. No annotations on the SA, no OIDC, no trust-policy regex.

## Add-ons — use the `aws_eks_addon` resource

Manage the core add-ons through EKS, not via Helm:

| Add-on | Notes |
|---|---|
| `vpc-cni` | Configure prefix delegation for pod density: `ENABLE_PREFIX_DELEGATION=true` |
| `coredns` | Sized via `resources` config; default OK for most |
| `kube-proxy` | Match cluster version |
| `aws-ebs-csi-driver` | Required for `PersistentVolumeClaim` |
| `eks-pod-identity-agent` | Required for Pod Identity |
| `metrics-server` | Replaces stand-alone Helm install |
| `amazon-cloudwatch-observability` | If using Container Insights |

```hcl
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}
```

Use `data "aws_eks_addon_version"` to look up the latest compatible version for the cluster's K8s version. Pin in code, bump deliberately.

### Non-core controllers

These usually go in via Helm — see the `helm` skill for chart consumption and the `flux` skill for `HelmRelease`-based reconciliation:

| Controller | Purpose |
|---|---|
| **AWS Load Balancer Controller** | ALB/NLB for Ingress / Service `type=LoadBalancer` |
| **Karpenter** | Node autoscaling (replaces Cluster Autoscaler) |
| **External DNS** | Route 53 records for Ingress hostnames |
| **External Secrets Operator** OR **1Password Connect/Reflector** | Sync external secrets into K8s |
| **Cert-Manager** | TLS via ACME (Let's Encrypt) or AWS Private CA |
| **Reloader** | Roll Deployments on ConfigMap/Secret change |

Christian's secrets convention is **1Password Operator + Reflector**, not ESO. See the `flux` skill.

## Networking — VPC CNI

EKS uses the **VPC CNI** by default: every pod gets a routable VPC IP. Pros: native AWS integration, security group support per-pod. Cons: pod density limited by ENI/IP allocation per instance.

Enable **prefix delegation** on the VPC CNI to massively expand pod density:

```hcl
resource "aws_eks_addon" "vpc_cni" {
  # ...
  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })
}
```

Without prefix delegation, an `m7g.large` can host ~29 pods. With it: 110.

### Subnet sizing

Each pod consumes an IP from the worker node's subnet. Plan accordingly:

- Worker subnets: **`/20`** minimum (4,000+ pods possible) — see [networking.md](networking.md).
- Use **secondary VPC CIDR** + dedicated CGNAT-range (`100.64.0.0/10`) for pod IPs if the primary CIDR is exhausted. Pods get non-routable IPs; node IPs stay routable.

### Security groups for pods

VPC CNI supports per-pod security groups via `SecurityGroupPolicy`. Useful when pods need different egress rules than the node (e.g. some pods reach RDS, others don't). Adds complexity — only when needed.

## Ingress

**AWS Load Balancer Controller** is the only ingress controller worth running in EKS for AWS-native LBs. Two flavors:

| Mode | Use |
|---|---|
| **`Ingress` + ALB** | Standard HTTP/HTTPS routing — most apps |
| **`Service type=LoadBalancer` + NLB** | TCP/UDP, very high throughput, static IPs |

Always annotate Ingress with `alb.ingress.kubernetes.io/scheme: internet-facing` (or `internal`), `alb.ingress.kubernetes.io/target-type: ip` (faster + works with Fargate), and `alb.ingress.kubernetes.io/load-balancer-attributes` for tuning.

Group multiple Ingresses onto **one ALB** via `alb.ingress.kubernetes.io/group.name=<group>` — one ALB per group instead of one per Ingress. Big cost saver.

For modern multi-cluster / multi-protocol routing, **Gateway API** is supported by the same controller — adopt for new work.

## Observability

| Need | Pick |
|---|---|
| Cluster metrics, control plane logs | **EKS control plane logs** (enabled above) + CloudWatch Container Insights |
| App metrics (Prometheus-style) | **Amazon Managed Prometheus** (AMP) + **Amazon Managed Grafana** (AMG) |
| Traces | AWS Distro for OpenTelemetry (ADOT) → AWS X-Ray or AMP |
| Logs | Fluent Bit → CloudWatch Logs or S3/OpenSearch |

CloudWatch Container Insights is the path-of-least-resistance default. If the cluster runs Prometheus exporters or already exports metrics in OTLP, AMP is the right move; Grafana via AMG saves running a stateful self-hosted instance.

## Secrets

Christian's house pattern is **1Password Operator + Reflector** (see the `flux` skill). Two-stage:

1. **1Password Operator** reads from a 1Password vault and creates K8s Secrets in a `onepassword` namespace.
2. **Reflector** copies/reflects those Secrets into the workloads' namespaces using annotations.

Don't:

- Use SOPS-encrypted secrets in Git (Christian's flux skill explicitly avoids this).
- Use AWS Secrets Manager directly mounted via Secrets Store CSI Driver as the only path — fine as a fallback, but not the default.
- Bake secrets into container images or ConfigMaps.

## Reconciliation — Flux

Cluster bootstrap order:

1. **Tofu** creates: cluster, node group for system workloads, core add-ons (vpc-cni, coredns, kube-proxy, ebs-csi, pod-identity-agent).
2. **Tofu** installs Flux via Helm (one-shot — Flux manages itself thereafter).
3. **Flux** reconciles everything else from Git: Karpenter, ALB controller, External DNS, 1Password operator, cert-manager, apps.

See the `flux` skill for the reconcile-chain pattern and the `helm` skill for chart authoring / OCI distribution. The AWS-side rule is: **don't install application workloads via Helm in Tofu**. Tofu does cluster + core add-ons; Flux does the rest.

## Inner-loop development — Skaffold

For "I want to iterate on a service against a real EKS cluster" — building images, syncing files, port-forwarding, attaching a debugger — use **Skaffold**, not Flux. Flux is for declarative production deploys; Skaffold is the fast feedback loop on the developer's laptop.

Typical pattern against EKS:

- Skaffold builds images locally, pushes to **ECR** (use the `ecr.api` / `ecr.dkr` VPC endpoints if the cluster is private — see [networking.md](networking.md)).
- Authenticate Docker to ECR via `aws ecr get-login-password`.
- Pod Identity / IRSA covers the deployed pods' AWS access during dev too — no separate dev IAM.

See the `skaffold` skill for the `skaffold.yaml` schema, profiles, sync rules, and `skaffold debug`.

## Naming

Cluster name follows [naming.md](naming.md):

```
prod-platform
nonprod-platform
sandbox-platform
```

The cluster name shows up in many other resources (OIDC issuer URL, IAM roles, log groups), so keep it short and stable.

## Cost watchpoints

- **Control plane**: $0.10/hour ($73/month) per cluster, always — don't proliferate clusters.
- **NAT egress** (pod → public registry): biggest surprise bill. Mirror images to ECR.
- **CloudWatch logs** with no retention.
- **ALBs per Ingress** when group annotation is missing — one ALB per Ingress at $20+/month each.
- **Spot interruption rate** — diversify instance families in Karpenter.

## Don't / Do

| Don't | Do |
|---|---|
| `version = "1.28"` while current GA is `1.32` | Stay N or N-1 from GA |
| `authentication_mode = "API_AND_CONFIG_MAP"` | `API` only |
| `bootstrap_cluster_creator_admin_permissions = true` | `false`; use explicit access entries |
| Stand up new IRSA for new workloads | Pod Identity |
| Cluster Autoscaler | Karpenter |
| Install Karpenter / ALB controller via Tofu Helm | Install via Flux (Tofu installs Flux only) |
| `x86_64` nodes | `arm64` (Graviton) |
| AL2 worker AMI | Bottlerocket or AL2023 |
| Public endpoint, no CIDR allowlist | Private + public with `public_access_cidrs` restricted |
| `aws-auth` ConfigMap edits | Access entries + policy associations |
| One ALB per Ingress | `alb.ingress.kubernetes.io/group.name` to share ALBs |
| Forget cluster logging | Enable at least `audit` and `authenticator` |
| `aws_eks_addon` left at default version | Pin via `aws_eks_addon_version` lookup, bump deliberately |
| Skip prefix delegation on VPC CNI | `ENABLE_PREFIX_DELEGATION=true` |
| Bake EKS secrets into AMIs / ConfigMaps | 1Password operator + Reflector (or ESO if forced) |
