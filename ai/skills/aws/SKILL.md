---
name: aws
description: AWS conventions — naming, tagging, IAM, networking, storage (S3/KMS/EBS), per-service defaults (EC2, Lambda, EKS). Use when the user mentions AWS services or works with `aws_*` HCL resources — 'create a bucket', 'add an IAM role', 'tag these resources', 'set up a VPC', 'configure EKS'. Defer HCL mechanics to `terraform`, API reads to `aws-mcp`.
compatibility: opencode
---

# AWS Conventions

AWS is a sprawl. Christian's house style is the small, opinionated subset that makes new infra readable a year later — naming, tags, IAM patterns, network layout, and per-service defaults for the things he actually uses (S3, EC2, Lambda, EKS, KMS). If a project already has its own conventions, **mirror the project**. The rules in this skill are the defaults for new work.

The most common AI failure mode is generating AWS infra that's "technically correct" but ignores the conventions that make day-2 ops bearable: names that bake in the resource type (`web-sg`), tags in PascalCase, IAM roles named after the person who created them, security groups with `0.0.0.0/0` ingress on port 22, S3 buckets with public access blocks off. Read the relevant topic file before authoring.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Name something — bucket, role, instance, function, SG, table | [naming.md](naming.md) |
| Tag something, set provider `default_tags`, or audit existing tags | [tagging.md](tagging.md) |
| Create an IAM role/policy, set up OIDC for CI, choose managed vs inline | [iam.md](iam.md) |
| Lay out a VPC, pick subnet tiers, write security groups, place NATs/endpoints | [networking.md](networking.md) |
| Configure an S3 bucket, choose KMS keys, set lifecycle policies, attach EBS volumes | [storage.md](storage.md) |
| Launch EC2, pick instance types/AMIs, choose on-demand/spot, set up SSM access | [ec2.md](ec2.md) |
| Write a Lambda, pick a runtime, configure triggers, set log retention | [lambda.md](lambda.md) |
| Build or modify an EKS cluster, choose node groups, set up IRSA / Pod Identity | [eks.md](eks.md) |

For one-off edits the cheat sheet below is usually enough. Reach for the topic files when the task warrants depth.

### Related skills — defer to these when they fit

| Topic | Skill |
|---|---|
| HCL mechanics (providers, modules, state, `tofu` CLI) | `terraform` |
| Reading current AWS state via the AWS API | `aws-mcp` |
| GitOps reconciliation into an EKS cluster (`HelmRelease`, `Kustomization`) | `flux` |
| Helm chart authoring, consumption, OCI distribution | `helm` |
| Kubernetes inner-loop dev workflow against EKS (build, sync, port-forward, debug) | `skaffold` |

## The default stack

| Concern | Default | Notes |
|---|---|---|
| IaC | **OpenTofu** (`tofu`) | Falls back to Terraform if a project pins it |
| AWS API access | **`aws` MCP** | Full tools; read freely, mutations need explicit auth — see `aws-mcp` |
| Default region | **`us-east-1`** | Most service coverage; multi-region only when workload demands it |
| Encryption | **On everywhere, KMS-backed** | S3 SSE-KMS, EBS encrypted, RDS encrypted, Secrets Manager KMS-backed; CMK per app boundary |
| IAM | **Roles, not users.** OIDC for CI, Identity Center for humans | No long-lived access keys in new work |
| Naming | `<env>-<app>-<purpose>[-<qualifier>]`, kebab-case | Don't repeat resource type — see [naming.md](naming.md) |
| Tagging | `<ns>:<key>` lowercase via `provider.default_tags` | See [tagging.md](tagging.md) |
| State (tofu) | **Per-environment remote state**, S3 + DynamoDB lock | Never check `*.tfstate` in |
| Logs | **CloudWatch**, finite retention | 30d non-prod, 365d prod; never "never expire" |
| Compute arch | **`arm64` / Graviton** where supported | EC2 (`m7g`/`c7g`/`r7g`), Lambda (`arm64`), EKS managed node groups |

## Universal rules

1. **Names identify; tags describe.** Anything that belongs in metadata (env, owner, cost center, data class) goes in tags, not the name.
2. **Tag everything via `provider.default_tags`.** Never repeat the standard set per resource. Per-resource `tags = {}` blocks are for resource-specific overrides only.
3. **No public access by default.** S3 buckets get `block_public_access = true`. Security groups never have `0.0.0.0/0` ingress except on port 80/443 for things explicitly meant to be public.
4. **No long-lived IAM access keys.** Use roles assumed via OIDC (CI/CD), Identity Center (humans), or instance profiles (EC2).
5. **Encryption at rest is on.** S3 SSE-KMS, EBS encrypted, RDS encrypted. Customer-managed KMS key per application boundary, not per resource.
6. **Logs go to CloudWatch with a finite retention.** Default 30d for non-prod, 365d for prod. Never leave at "never expire" — it's the silent cost killer.
7. **Multi-AZ for anything stateful.** Single-AZ is fine for stateless; not for RDS, ElastiCache, persistent EBS-backed services.
8. **Smallest viable IAM policy.** No `*:*`. No `Resource: *` outside of read-only or service-link policies. Prefer AWS-managed policies for common patterns; inline only for tightly-coupled role+policy pairs.
9. **No PII, secrets, or account IDs in names or tags.** Tags are visible to billing, Cost Explorer, and many service APIs.
10. **Current-gen instance families only.** New work uses `m7`/`c7`/`r7` (or `g` variants), not `m5`/`c5`/`r5`. Old gens cost more for less.

## Naming + tagging cheat sheet

Pattern:

```
<env>-<app>-<purpose>[-<qualifier>]

prod-checkout-api
prod-checkout-api-blue          # blue/green
prod-checkout-redis             # purpose, not "redis-cluster"
nonprod-shared-egress           # qualifier when one app has multiples
```

Tag keys:

```
christian:<key>          # personal accounts
<company>:<key>          # work accounts — match the org's existing prefix
```

Required tag set (applied via `provider.default_tags`):

| Key | Example |
|---|---|
| `<ns>:environment` | `prod`, `nonprod`, `sandbox` |
| `<ns>:application` | `checkout`, `auth`, `platform` |
| `<ns>:owner` | `christian@…` or team handle |
| `<ns>:managed-by` | `tofu`, `terraform`, `manual` |

| Don't | Do |
|---|---|
| `web-sg`, `app-bucket`, `auth-lambda` (resource type in name) | `web`, `app-assets`, `auth` |
| `Environment`, `CostCenter` (PascalCase tag keys) | `christian:environment`, `christian:cost-center` |
| Tag every resource by hand | `provider.default_tags` block |
| Mix tag-key casing (`Environment` and `environment`) | One casing, forever |
| Hardcode account IDs in names | Use tags / data sources |

Full rules: [naming.md](naming.md), [tagging.md](tagging.md).

## Adding to this skill

When a new convention or strong preference lands, add it to the relevant topic file (or create a new one and link it from the decision tree). Keep `SKILL.md` lean — the decision tree is the contract, the depth lives in topic files.

After editing anything in this skill, run `dot install` to refresh the symlinks across all three tools.
