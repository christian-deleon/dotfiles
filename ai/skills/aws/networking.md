# Networking

A VPC is a private IPv4 (and optionally IPv6) network you carve into subnets across AZs. Almost every AWS workload eventually lands in one. The mental model: **VPC = CIDR + AZs; subnets = AZ-pinned slices typed by routing; security groups = stateful workload-to-workload allow-lists; route tables = where traffic goes.** Most networking mistakes are at one of those four layers, and most of them are visible at `tofu plan` time if you know what you're looking for.

The most common AI failure mode: collapsing all subnets onto one route table, putting everything in "public" because it's easier, opening security groups to `0.0.0.0/0` for app-to-app traffic, and forgetting the egress side entirely (NAT, endpoints).

## VPC layout

Default to **one VPC per environment** (per region) with a `/16` and three subnet tiers across three AZs.

```
VPC CIDR             10.0.0.0/16      (65k addresses)
├── Public           10.0.0.0/20      AZ-a   /24 ×3 — internet-facing LBs only
├── Public           10.0.16.0/20     AZ-b
├── Public           10.0.32.0/20     AZ-c
├── Private          10.0.64.0/20     AZ-a   /20 ×3 — app workloads (EC2, ECS, EKS, Lambda)
├── Private          10.0.80.0/20     AZ-b
├── Private          10.0.96.0/20     AZ-c
├── Isolated         10.0.128.0/20    AZ-a   /20 ×3 — databases, internal-only state
├── Isolated         10.0.144.0/20    AZ-b
└── Isolated         10.0.160.0/20    AZ-c
```

| Tier | Route to internet | Use for |
|---|---|---|
| **Public** | IGW (in + out) | ALB/NLB internet-facing, NAT gateway, bastion if you still have one |
| **Private** | NAT only (out, no in) | App workloads — anything that needs egress but not direct ingress |
| **Isolated** | None | RDS, ElastiCache, anything that should never reach the internet |

A `/20` is **4,096 addresses** per subnet. AWS reserves 5 per subnet, EKS eats a few per pod with VPC CNI — `/20` is the floor for any subnet that holds pods. For non-EKS workloads `/24` (256) is usually plenty.

### Don't pick CIDRs at random

Plan the CIDR before any VPC exists. Common conventions:

| Use | CIDR |
|---|---|
| `prod` (us-east-1) | `10.0.0.0/16` |
| `prod` (us-west-2) | `10.1.0.0/16` |
| `nonprod` (us-east-1) | `10.10.0.0/16` |
| `nonprod` (us-west-2) | `10.11.0.0/16` |
| `sandbox` | `10.100.0.0/16` |

Never overlap with corporate office CIDRs, VPN ranges, or any other VPC you'll peer with. Once a VPC exists, you can add **secondary CIDRs** but you can't change the primary — pick deliberately.

Avoid `172.16.0.0/12` and `192.168.0.0/16` if you'll ever VPN home — those collide with home routers (`192.168.1.0/24`) and many corporate networks (`172.16.x.x`).

### Three AZs, not two

AWS bills the same for 2 vs 3, but a single-AZ failure with two AZs takes 50% of capacity offline; with three AZs it takes 33%. ALB/NLB require 2 AZs minimum, RDS Multi-AZ uses 2 AZs, EKS prefers 3. Default to 3.

A handful of regions only have 2 AZs (some China/Gov regions). Check `data "aws_availability_zones"` before assuming 3.

## Subnet naming

Subnets get the standard `<env>-<app>-<purpose>` shape, with the tier and AZ as the purpose:

```
prod-platform-public-a
prod-platform-public-b
prod-platform-public-c
prod-platform-private-a
prod-platform-private-b
prod-platform-private-c
prod-platform-isolated-a
prod-platform-isolated-b
prod-platform-isolated-c
```

`<app>` is usually `platform` or `shared` when the VPC is shared across applications (the common case). Per-app VPCs are rare and usually wrong.

## NAT gateways

NAT gateways are the single most-expensive cheap-looking AWS resource — they bill per-hour **and** per-GB processed.

| Layout | Cost | Resilience |
|---|---|---|
| **One NAT per AZ** | 3× hourly cost, full AZ resilience | Default for prod |
| **One NAT total** | 1× hourly cost, no AZ resilience | Acceptable for nonprod/sandbox |
| **NAT instances (self-hosted)** | Cheapest, more ops | Only when you have someone to own the AMI |

Per-AZ NAT is the prod default. Per-AZ also avoids the cross-AZ data transfer charge that single-NAT inflicts on traffic from other AZs.

Each private subnet's route table sends `0.0.0.0/0` to the NAT **in the same AZ**:

```hcl
resource "aws_route" "private_nat" {
  for_each               = aws_route_table.private  # one per AZ
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}
```

## VPC endpoints — cut the NAT bill

For traffic to AWS services, **VPC endpoints** avoid the NAT entirely:

| Endpoint | Type | Use |
|---|---|---|
| `s3` | **Gateway** (free) | Always. S3 traffic is the biggest NAT cost driver. |
| `dynamodb` | **Gateway** (free) | Always if you use DDB. |
| `ecr.api`, `ecr.dkr` | Interface ($0.01/hr × AZ) | EKS/ECS pulling images from ECR |
| `logs` (CloudWatch) | Interface | Container log shipping |
| `sts` | Interface | IRSA token calls (high-frequency in EKS) |
| `ssm`, `ssmmessages`, `ec2messages` | Interface | SSM Session Manager without internet |
| `secretsmanager` | Interface | Secrets reads from private workloads |
| `kms` | Interface | Lots of crypto operations |

Gateway endpoints are free; create them by default. Interface endpoints cost ~$22/month/AZ — only create them when the NAT data charges are higher (they often are for ECR/logs).

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
}
```

## Security groups

Stateful, allow-list. Outbound is unrestricted by default unless you tighten it (rarely worth it for app SGs).

### Naming + purpose

Name by what the SG **fronts**, not its layer:

```
prod-checkout-api          # SG for the checkout API workloads
prod-checkout-redis        # SG for checkout's Redis cluster
prod-checkout-rds          # SG for checkout's RDS instance
```

Not `prod-checkout-app-sg`, not `prod-checkout-public-sg`.

### Reference SGs, not CIDRs

For app-to-app traffic, the **source is another SG**, not a CIDR block:

```hcl
resource "aws_security_group" "redis" {
  name   = "prod-checkout-redis"
  vpc_id = aws_vpc.this.id
}

resource "aws_security_group_rule" "redis_from_api" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.api.id   # SG-to-SG
  security_group_id        = aws_security_group.redis.id
}
```

CIDRs only for:

- Public-facing rules (ALB ingress `0.0.0.0/0` on 443).
- On-prem / corporate VPN ranges (the office's `203.0.113.0/24`).
- Cross-VPC peering / Transit Gateway where SG references aren't available.

### Egress

The implicit default egress is `0.0.0.0/0 all ports`. For most app SGs, leave it. Restrict egress only when:

- The workload should genuinely never call out (database servers).
- Compliance requires it.

If you do restrict, **list specific destinations** — restricting to `0.0.0.0/0` on port 443 alone is mostly theater.

### Don't do this

```hcl
# anti-pattern
resource "aws_security_group_rule" "open_ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]   # 🚨
  # ...
}
```

For SSH-like access use **SSM Session Manager** (see [ec2.md](ec2.md)) — no inbound port, no bastion, full audit trail.

### Rule limits

- Default: **60 rules per SG per direction** (so 120 total). Quota-raisable.
- Hard cap: SG references across VPCs work only via peering with the right config; outside of that, fall back to CIDR.

If you find yourself bumping the limit, you probably want fewer, larger SGs — or a different layer (WAF, NACL) doing the filtering.

## NACLs

Default NACL allows everything in/out. The right answer is **leave it alone** in 99% of cases and do filtering with SGs.

NACLs are useful for:

- Subnet-level deny rules that no SG can override (block an IP range from any workload in this subnet).
- Compliance frameworks that mandate "defense in depth at the network layer".

When you do use them, remember they're **stateless** — you must allow both directions explicitly, including ephemeral return ports (typically `1024–65535`).

## VPC peering / Transit Gateway

| Scale | Use |
|---|---|
| 2 VPCs, occasional | VPC peering |
| 3+ VPCs, on-prem connectivity, hub-and-spoke | Transit Gateway |

VPC peering doesn't support transitive routing — A↔B and B↔C does not give you A↔C. Transit Gateway does, with optional route-table partitioning for segmentation.

Either way, plan CIDRs to **never overlap**. Peering with overlapping CIDRs requires NAT in the middle and is its own ops nightmare.

## DNS

In Route 53:

- **Public hosted zone** for the public domain (`example.com`).
- **Private hosted zone** for internal records, attached to the VPC. Lets workloads resolve `db.internal.example.com` without it being public.
- **Route 53 Resolver inbound/outbound endpoints** when you need to share DNS with on-prem or other VPCs.

Set `enable_dns_hostnames = true` and `enable_dns_support = true` on the VPC. Without them, instances don't get DNS hostnames and several AWS services break in subtle ways.

## IPv6

Default new VPCs to **dual-stack** (IPv4 + IPv6) — AWS no longer charges for public IPv4 only because they're generous, they charge because they're scarce. IPv6 is free, the egress-only internet gateway is free, and any new service that's IPv6-aware will save you money.

```hcl
resource "aws_vpc" "this" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true
}
```

If the workload is IPv4-only, leave the IPv6 CIDR allocated and unused — you can't add it later without disruption on some configurations.

## Public IP charges

As of February 2024, AWS charges $0.005/hr per **public IPv4 address**, whether attached or not. Two things follow:

1. Don't auto-assign public IPs on private-subnet instances. Belt-and-suspenders: `map_public_ip_on_launch = false` on private subnets even though there's no IGW to use them.
2. Watch idle Elastic IPs — they bill whether attached or not.

## Don't / Do

| Don't | Do |
|---|---|
| One subnet per VPC, all `0.0.0.0/0` via IGW | 3 tiers × 3 AZs, route by tier |
| `0.0.0.0/0` ingress on port 22 (SSH) | SSM Session Manager — no inbound port |
| SG referencing a CIDR for app-to-app | SG referencing the source SG |
| One NAT in prod | One NAT per AZ for prod |
| No S3/DDB gateway endpoint | Always create both (free) |
| `Allow all from 0.0.0.0/0` "temporarily" | A specific port + a specific source |
| Pick a CIDR ad-hoc | Plan the CIDR map before any VPC exists |
| Two AZs because three feels excessive | Three AZs; AWS doesn't charge more |
| Use NACLs as your primary filter | SGs are primary; NACLs only for subnet-level deny |
| VPC peering for 5 VPCs and a Direct Connect | Transit Gateway |
| Forget `enable_dns_hostnames` | Set both DNS toggles to `true` |
| Leave `assign_generated_ipv6_cidr_block = false` on new VPCs | Default dual-stack |
