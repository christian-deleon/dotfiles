# EC2

EC2 is the bare-metal default for "I need a Linux box in AWS". The mental model: **an instance is an AMI + an instance type + an ENI + an instance profile**, scheduled in a subnet you chose. The right default for new workloads in 2026 is **Graviton (ARM64) on `m7g`/`c7g`/`r7g`, AL2023, `gp3` root volume, IMDSv2 required, SSM Session Manager for access, behind an ASG with a launch template**. Anything that diverges from that should have a reason.

The most common AI failure mode: an `m5.large` (old gen, x86), Amazon Linux 2 (EOL'd 2025), `gp2` root volume, IMDSv1 enabled, an SSH bastion with a `0.0.0.0/0:22` security group, and an instance profile attached after creation by hand.

## Default instance choice

| Concern | Default |
|---|---|
| Family | **`m7g`** for general workloads, `c7g` CPU-bound, `r7g` memory-bound |
| Architecture | **`arm64`** (Graviton) — ~20% cheaper, ~40% better perf/W |
| Size | Smallest that hits SLOs, scale horizontally |
| AMI | **Amazon Linux 2023** (AL2023) for vanilla; Ubuntu LTS or Bottlerocket if the workload needs it |
| Tenancy | **Shared** — `dedicated` only when a contract requires it |
| EBS | **`gp3`** root, 30 GB, encrypted with the app CMK |
| IMDS | **IMDSv2 required** (`http_tokens = "required"`) |
| Access | **SSM Session Manager** — no SSH, no bastion |
| Pricing | Spot for nonprod/stateless; on-demand for prod; Savings Plans for steady-state |
| Lifecycle | **ASG + launch template**, never standalone `aws_instance` for production |

### Why ARM-first

Graviton is the default unless something blocks it. Blockers worth checking:

- Software with no ARM build (rare in 2026, but check). `docker pull` shows it immediately.
- Vendor agents (some legacy monitoring/security agents lag).
- Native libs the app builds against (sometimes need a `linux/arm64` wheel/binary).

When ARM is blocked, fall back to **`m7i`/`c7i`/`r7i`** (Intel) or **`m7a`/`c7a`/`r7a`** (AMD) — same generation, x86. Never fall back to `m5`/`c5`/`r5` — old gen is more expensive and slower than current gen.

### Instance generation cheat sheet

| Letter | Meaning |
|---|---|
| `g` | Graviton (ARM64) — default |
| `i` | Intel — fall back |
| `a` | AMD — sometimes cheapest |
| `n` | Network-optimized variant (e.g. `m7gn`) |
| `d` | Local NVMe storage variant |

## AMIs

### Picking one

Don't pin to a fixed AMI ID — it's region-specific and rots. Look it up with `aws_ami`:

```hcl
data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}
```

For Ubuntu, use **Canonical's `099720109477`**. For Bottlerocket, use **`bottlerocket-aws/aws-k8s-1.32-aarch64`** (or the matching K8s version).

### Custom AMIs

For anything more complex than "install one package on boot", **bake an AMI** with Packer (HashiCorp) or **EC2 Image Builder**. User-data scripts are fine for ~10 lines of bootstrap; past that, they slow boot, hide failure modes, and re-run on every replacement.

Naming and tagging for custom AMIs follow the standard pattern:

```
prod-checkout-api-2026-05-19
```

Tag the AMI with `<ns>:application`, `<ns>:base-ami` (the source), and `<ns>:built-at`.

### AMI lifecycle

- Set `deprecation_time` on AMIs you replace. After that, new launches fail with a clear error.
- After 60+ days deprecated, deregister the AMI — and **delete the underlying snapshots** (deregistering doesn't delete them, this is a frequent surprise on the EBS bill).

## Launch templates and ASGs

Always use a **launch template** (not the older launch configuration — it's deprecated). Always put production workloads behind an ASG, even if the desired capacity is 1, so a replacement can self-heal.

```hcl
resource "aws_launch_template" "api" {
  name_prefix   = "prod-checkout-api-"
  image_id      = data.aws_ami.al2023_arm64.id
  instance_type = "m7g.large"
  key_name      = null   # no SSH key — SSM only

  iam_instance_profile {
    arn = aws_iam_instance_profile.api.arn
  }

  vpc_security_group_ids = [aws_security_group.api.id]

  metadata_options {
    http_tokens                 = "required"   # IMDSv2 required
    http_put_response_hop_limit = 2            # pods/containers need 2 hops
    http_endpoint               = "enabled"
    instance_metadata_tags      = "enabled"    # exposes instance tags via IMDS
  }

  monitoring {
    enabled = true   # 1-minute CloudWatch metrics
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.checkout.arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "prod-checkout-api"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "prod-checkout-api"
    }
  }
}
```

The two `tag_specifications` blocks are not optional — `default_tags` doesn't propagate to ASG-launched instances/volumes automatically.

### ASG patterns

```hcl
resource "aws_autoscaling_group" "api" {
  name                = "prod-checkout-api"
  min_size            = 3
  max_size            = 10
  desired_capacity    = 3
  vpc_zone_identifier = aws_subnet.private[*].id   # all three AZs
  health_check_type   = "ELB"                       # mark unhealthy on ALB target failure
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.api.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 66
    }
    triggers = ["tag"]
  }

  target_group_arns = [aws_lb_target_group.api.arn]

  # Spread across AZs — never all in one AZ
}
```

`instance_refresh` rolls instances on launch-template version bumps; without it you'll have an ASG running an old AMI forever.

### Spot vs on-demand

Use `MixedInstancesPolicy`:

```hcl
mixed_instances_policy {
  instances_distribution {
    on_demand_base_capacity                  = 1   # always at least one on-demand
    on_demand_percentage_above_base_capacity = 0   # rest can be spot
    spot_allocation_strategy                 = "price-capacity-optimized"
  }

  launch_template {
    launch_template_specification { ... }

    override { instance_type = "m7g.large" }
    override { instance_type = "m7g.xlarge" }
    override { instance_type = "m6g.large" }       # diversify across types
  }
}
```

Spot rules of thumb:

- **Nonprod / stateless workers**: 100% spot, fall back to on-demand on capacity exhaustion.
- **Prod stateless front-ends**: spot with on-demand base (1–25%), `price-capacity-optimized`.
- **Stateful or hard-to-replace**: on-demand, with Savings Plans / Reserved Instances if the workload is steady.

Spot can be interrupted with **2-minute warning** via the IMDS metadata path `/latest/meta-data/spot/instance-action`. Graceful-drain on this signal — workloads that don't are a liability.

## IAM — instance profiles

Every EC2 instance gets an instance profile, even if the only permission is "write logs to CloudWatch". Profiles bridge IAM roles into EC2.

```hcl
resource "aws_iam_role" "api" {
  name               = "prod-checkout-api"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "api" {
  name = aws_iam_role.api.name   # match — easier to find
  role = aws_iam_role.api.name
}
```

Always attach the **AmazonSSMManagedInstanceCore** managed policy plus **CloudWatchAgentServerPolicy** — they're the floor for any instance you want to be operable.

```hcl
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

App-specific permissions on top of those, customer-managed.

## IMDSv2 — non-negotiable

IMDSv1 has been the source of multiple high-profile credential exfiltration incidents (Capital One, etc.). **Always require IMDSv2** on new launch templates:

```hcl
metadata_options {
  http_tokens                 = "required"
  http_put_response_hop_limit = 2
  http_endpoint               = "enabled"
}
```

- `http_tokens = "required"` rejects IMDSv1 calls.
- `http_put_response_hop_limit = 2` allows container workloads (Docker, Kubernetes) to reach IMDS through the pod network. The default `1` blocks them.
- `instance_metadata_tags = "enabled"` exposes the instance tags at `/latest/meta-data/tags/instance/`, useful for bootstrap.

## SSM Session Manager — no SSH

Stop building SSH bastions in 2026. **AWS Systems Manager Session Manager** gives you:

- Audited shell access (CloudTrail + optional session logs to S3/CloudWatch).
- No inbound port, no key management, no `0.0.0.0/0:22`.
- IAM-controlled access — `ssm:StartSession` on `arn:aws:ec2:…:instance/<id>`.

What's required:

1. SSM agent running on the instance (preinstalled on AL2023, Ubuntu 20.04+, Bottlerocket).
2. Instance has the `AmazonSSMManagedInstanceCore` managed policy.
3. SSM endpoints reachable — either via NAT or **VPC interface endpoints for `ssm`, `ssmmessages`, `ec2messages`** (for fully-private subnets, see [networking.md](networking.md)).

Connect:

```sh
aws ssm start-session --target i-0123456789abcdef0
```

For port forwarding (e.g. RDP, internal HTTP):

```sh
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=8080,localPortNumber=8080
```

The dotfiles repo's `ssmpf`/`ssmpfh`/`ssmrun` shell functions wrap these — use them instead of remembering the flags.

If a workload genuinely needs SSH (e.g. legacy interactive use), use **EC2 Instance Connect Endpoint** (one resource per VPC, no SG inbound on the instance) — still better than a bastion.

## Storage on instances

| Need | Use |
|---|---|
| Root disk | `gp3`, encrypted, sized to actual need |
| Working scratch space | **Instance store** (`*d` types like `m7gd`) — free, ephemeral, lost on stop |
| Persistent state | **EBS data volume** (`gp3`), separate from root, encrypted |
| Shared across instances | **EFS** for POSIX shared FS, **FSx** for Windows/HPC |
| Object storage | **S3** — see [storage.md](storage.md) |

Don't put state on the root volume. A separate EBS data volume can be detached and reattached during instance replacement; the root volume can't (cleanly).

## Logs and metrics

The CloudWatch Agent ships logs + metrics. Install it via Distributor or bake into the AMI; configure with SSM Parameter Store so config changes don't require an AMI rebuild.

Default log destinations:

| Log | Destination |
|---|---|
| App stdout/stderr | `/aws/ec2/<env>-<app>` log group, structured JSON |
| `/var/log/messages` | `/aws/ec2/<env>-<app>/system` |
| Auth log | `/aws/ec2/<env>-<app>/auth` (audit trail) |

Set log retention explicitly on the log group (30d nonprod, 365d prod). The default is "never expire".

## Don't / Do

| Don't | Do |
|---|---|
| `m5.large` for new work | `m7g.large` (or `m7i` if ARM blocked) |
| Amazon Linux 2 | Amazon Linux 2023 |
| `gp2` root volume | `gp3`, encrypted with app CMK |
| `http_tokens = "optional"` / IMDSv1 | `http_tokens = "required"` |
| SSH bastion with `0.0.0.0/0:22` | SSM Session Manager |
| Long user-data script for setup | Bake an AMI (Packer / Image Builder) |
| Standalone `aws_instance` in prod | ASG + launch template, even for capacity 1 |
| Pin AMI by hardcoded ID | `data "aws_ami"` with most_recent + filter |
| All-on-demand for nonprod | Spot with on-demand base |
| Attach instance profile by hand | Define profile in HCL alongside the role |
| Forget `tag_specifications` for ASG-launched instances | Set them for `instance` and `volume` |
| Keep AMIs forever | Deprecate, then deregister + delete snapshots |
| Put state on the root volume | Separate EBS data volume |
| Default CloudWatch log retention ("never expire") | Set explicit retention (30d / 365d) |
