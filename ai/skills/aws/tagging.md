# Tagging

Tags carry the metadata that names don't — ownership, billing attribution, lifecycle, classification. They're the join key between AWS resources and everything outside AWS (cost reports, CMDB, alerting, compliance scans). The most common failure mode is treating tags as an afterthought: missing on half the resources, inconsistent casing, duplicated info from the name. Tags are the contract — apply them via `provider.default_tags` and audit them.

## Tag key format

```
christian:<key>          # personal accounts
<company>:<key>          # work accounts — match the org's existing prefix
```

The namespace prefix prevents collisions with `aws:*` system tags and third-party tool tags (`kubernetes.io/*`, `elasticbeanstalk:*`, `Datadog:*`). Keys are **lowercase + hyphens** (`cost-center`, not `CostCenter`) — AWS's own generated tags follow this style and IAM has extra validation that rejects keys differing only in case.

## Default tag set

Every taggable resource carries:

| Key | Example value | Purpose |
|---|---|---|
| `<ns>:environment` | `prod`, `nonprod`, `sandbox` | Filter cost, scope alarms, gate access |
| `<ns>:application` | `checkout`, `auth`, `platform` | Cost allocation by team/product |
| `<ns>:owner` | `christian@…` or team handle | Who to ping when this resource pages |
| `<ns>:managed-by` | `tofu`, `terraform`, `manual` | Drift detection — anything `manual` is suspect |

Add others as needed (one per row, not many in one tag value):

| Key | When |
|---|---|
| `<ns>:cost-center` | Finance needs cost reports broken down past `application` |
| `<ns>:data-classification` | `public`, `internal`, `confidential`, `restricted` — anything storing data |
| `<ns>:repo` | `github.com/<org>/<repo>` — find the source for this resource |
| `<ns>:expires-on` | `2026-12-31` — used by janitor scripts for sandbox cleanup |
| `<ns>:tier` | `staging`, `qa`, `uat` — sub-split within `nonprod` |
| `<ns>:compliance` | `pci`, `hipaa`, `soc2` — gate IAM/policy decisions on this |
| `<ns>:backup` | `daily`, `weekly`, `none` — drives backup policy |

**Add a tag only when something will actually consume it.** A tag nobody reads is just noise that drifts.

## Apply via `default_tags`, not per-resource

In OpenTofu/Terraform, set the required tags once on the provider:

```hcl
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      "christian:environment" = var.environment
      "christian:application" = var.application
      "christian:owner"       = var.owner
      "christian:managed-by"  = "tofu"
    }
  }
}
```

Per-resource `tags = { ... }` blocks **merge with** `default_tags` — only put resource-specific overrides there:

```hcl
resource "aws_s3_bucket" "uploads" {
  bucket = "prod-checkout-uploads"

  tags = {
    "christian:data-classification" = "confidential"  # extra for this bucket
    Name                            = "prod-checkout-uploads"  # EC2/RDS-style
  }
}
```

If you set the same key in both `default_tags` and the resource `tags`, the resource wins. Don't repeat the standard set on every resource — that's what `default_tags` is for.

### Multi-provider gotcha

Each `provider "aws"` aliased block needs its own `default_tags`. They don't inherit:

```hcl
provider "aws" {
  alias  = "us_west"
  region = "us-west-2"

  default_tags {  # required — not inherited from the default provider
    tags = local.common_tags
  }
}
```

Pull the tag map into `locals.common_tags` so the two provider blocks stay in sync.

### Tags on resources that don't support `default_tags`

A handful of resources don't pick up `default_tags` automatically — they need explicit `tags`:

- `aws_autoscaling_group` (uses `tag {}` blocks with `propagate_at_launch`, not `tags = {}`)
- Some EBS volumes attached after instance creation (`aws_ebs_volume` is fine; volumes created by `aws_instance.root_block_device` may not propagate — check `volume_tags` on the instance)
- `aws_launch_template` tag_specifications: set explicitly per resource type (`instance`, `volume`, `network-interface`)

ASG example:

```hcl
resource "aws_autoscaling_group" "api" {
  # ...

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
```

## Tag gotchas

- **Max 50 user tags per resource.** AWS reserves the `aws:*` namespace; those don't count toward the 50.
- **Keys: 1–128 chars. Values: 0–256 chars.** Both UTF-8. Avoid characters outside `[a-zA-Z0-9 +\-=._:/@]` — some services reject them.
- **Tags are case-sensitive.** Never have `Environment` and `environment` on different resources. Pick one casing and enforce it.
- **Don't put secrets or PII in tags.** Tags are visible to billing, Cost Explorer, Resource Groups, AWS Config, Tag Editor, and many service APIs — including read-only ones a junior engineer can access.
- **Tag-based IAM conditions are real** (`aws:RequestTag`, `aws:ResourceTag`). If you use them, document which tags are policy-load-bearing — renaming `environment` to `env` will break access.
- **Cost allocation tags must be activated.** A tag isn't visible in Cost Explorer/CUR until you activate it in **Billing → Cost Allocation Tags**. New tag keys = invisible until activated.
- **Tag changes can be slow to propagate** to billing (up to 24h) and to some service-specific filters (ASG instance tags propagate at next refresh, not immediately).

## Cost allocation pattern

If finance cares about per-team / per-product spend, the minimum activated tags are:

```
<ns>:environment
<ns>:application
<ns>:owner
<ns>:cost-center
```

Activate them in Billing once, then they show up as CUR columns. Anything left untagged shows as `(not tagged)` in Cost Explorer — that's your work queue.

## Auditing existing tags

When you walk into an existing account, the first question is "what's tagged with what, and where's the drift". Use the `aws-mcp` skill to call `resourcegroupstaggingapi` and `Get Resources` — see that skill for invocation. Untagged or wrong-namespace resources go in a remediation backlog; **don't bulk-rewrite tags** without coordination, because IAM policies and Cost Explorer reports may depend on the current shape.

## Don't / Do

| Don't | Do |
|---|---|
| `Environment`, `CostCenter` (PascalCase) | `christian:environment`, `christian:cost-center` |
| `env` + `environment` on different resources | One key, forever |
| Tag every resource manually | `provider.default_tags` block |
| Stuff multiple values in one tag (`tags = "prod,checkout,api"`) | One key per concept |
| Tags that duplicate the name (`<ns>:name = "prod-checkout-api"`) | The Name tag exists for EC2; nothing else needs it |
| Account ID in tags | Implicit from the account; use Organizations + aliases |
| Secret/PII in tags | Tags are read by many services + people |
| Set up tags without activating them in Billing | Activate the cost-allocation tags day one |
| `<ns>:created-by = "tofu"` | Use `<ns>:managed-by` — `created-by` rots when ownership moves |
