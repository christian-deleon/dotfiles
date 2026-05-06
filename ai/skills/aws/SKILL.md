---
name: aws
description: Christian's AWS conventions — naming and tagging today, more workflow preferences over time. Activate when the user mentions AWS or any AWS service (S3, EC2, RDS, IAM, VPC, Lambda, etc.), works with `aws_*` resources in HCL, edits files referencing AWS ARNs/account IDs, or designs/reviews AWS infrastructure. Most commonly applies alongside the `terraform` skill (OpenTofu by default). Defer HCL mechanics to the `terraform` skill and AWS API reads to the `aws-mcp` skill.
compatibility: opencode
---

# AWS Conventions

Christian's house style for AWS. Today this is naming and tagging — more conventions land here over time.

If a project already has its own conventions, **mirror the project**. The rules below are the defaults for new work.

## Naming

**Names identify; tags describe.** A name is a short, human-readable identifier. Anything that belongs in metadata (env, owner, cost center, data class) goes in **tags**, not the name.

Hard rules:

- **Don't repeat the resource type in the name.** A security group is already a security group — don't call it `web-sg` or `app-securitygroup`. Same for `-bucket`, `-instance`, `-role`, `-lambda`, `-queue`, `-table`. The ARN, console, and provider already say what kind of thing it is.
- **kebab-case, lowercase, alphanumeric + hyphens only.** No underscores, no camelCase, no spaces.
- **Start and end with a letter or number.** No leading/trailing/double hyphens.
- **No PII, no AWS account IDs, no secrets** in names.

Default pattern when starting fresh:

```
<env>-<app>-<purpose>[-<qualifier>]

prod-checkout-api
prod-checkout-api-blue          # blue/green
prod-checkout-redis             # purpose, not "redis-cluster"
nonprod-shared-egress           # qualifier when one app has multiple of a thing
```

Use **purpose**, not type. `prod-checkout-redis` (purpose: cache for checkout) beats `prod-checkout-redis-cluster` (cluster is a redundant type word).

### Length traps

AWS resource name limits vary. Check before composing long names:

| Resource | Max name |
|---|---|
| S3 bucket | 63 (also DNS-safe: lowercase, no underscores, no consecutive dots) |
| IAM role / user / policy | 64 |
| Lambda function | 64 |
| RDS DB instance identifier | 63 |
| CloudWatch log group | 512 |

If a long pattern won't fit, abbreviate the **environment** (`p`/`np`/`stg`) before abbreviating the application — application identity is what humans search by.

## Tagging

Tags carry the metadata that names don't. Follow AWS's own tag style: lowercase keys, hyphen-separated, namespaced with a colon prefix.

### Tag key format

```
christian:<key>          # personal accounts
<company>:<key>          # work accounts — match the org's existing prefix
```

The namespace prefix prevents collisions with `aws:*` system tags and third-party tool tags. Keys are lowercase + hyphens (`cost-center`, not `CostCenter`) — AWS's own generated tags follow this style and IAM has extra validation that rejects keys differing only in case.

### Default tag set

Every taggable resource carries:

| Key | Example value |
|---|---|
| `<ns>:environment` | `prod`, `nonprod`, `sandbox` |
| `<ns>:application` | `checkout`, `auth`, `platform` |
| `<ns>:owner` | `christian@…` or team handle |
| `<ns>:managed-by` | `tofu`, `terraform`, `manual` |

Add others as needed (`cost-center`, `data-classification`, `repo`, `expires-on`) — but only when something will actually consume them.

### Apply via `default_tags`, not per-resource

In tofu, set the required tags once on the provider:

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

Per-resource `tags = { ... }` blocks merge with `default_tags` — only put resource-specific overrides there. Don't repeat the standard set on every resource.

### Tag gotchas

- Max **50 user tags** per resource. Tag keys 1–128 chars, values 0–256 chars (UTF-8).
- Tags are **case-sensitive** — never have `Environment` and `environment` on different resources.
- **Don't put secrets or PII in tags.** Tags are visible to billing, Cost Explorer, and many service APIs.

## Don't / Do

| Don't | Do |
|---|---|
| Repeat resource type in name (`web-sg`, `app-bucket`, `auth-lambda`) | Purpose-based name (`web`, `app-assets`, `auth`) |
| `Environment`, `CostCenter` (PascalCase tag keys) | `christian:environment`, `christian:cost-center` |
| Tag every resource manually | `provider.default_tags` block |
| Mix tag-key casing (`Environment` and `environment`) | Pick one style and stick to it |

## Adding to this skill

This skill grows. When Christian decides on a new convention, workflow, or strong preference, add a section for it. Keep examples short, lead with the rule, and call out the "why" only when it isn't obvious.
