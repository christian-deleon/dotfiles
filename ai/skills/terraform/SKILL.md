---
name: terraform
description: Modern Terraform / OpenTofu authoring (HCL). ALWAYS use when editing `*.tf`, `*.tofu`, `terraform.tfvars`, `.terraform.lock.hcl`, files under `terraform/` or `environments/` trees, or for prompts mentioning Terraform, OpenTofu, HCL, providers, modules, state, `terraform apply`/`plan`, `tofu` CLI, or 'add a resource', 'fix the variable', 'update the module', 'plan this'. Default to `tofu` in examples (the user's primary tool); call out features that exist only in Terraform or only in OpenTofu.
compatibility: opencode
---

# Terraform / OpenTofu Authoring

Terraform and OpenTofu share the same HCL language and most features. Treat them as one tool unless a feature is version- or fork-specific. The user's default is **OpenTofu** (`tofu` CLI); they only use Terraform proper at work where it's mandated. Use `tofu` in examples; commands are identical for `terraform` unless noted.

If you can't tell which is in use, check for a `tofu` binary on PATH, a `.tofu` override file, or an `encryption` block (OpenTofu-only); otherwise ask.

## Project layout

```
terraform/
├── modules/<module_name>/
│   ├── versions.tf        # required_providers (no version pin — caller controls)
│   ├── variables.tf
│   ├── main.tf
│   └── outputs.tf
└── environments/<cloud>/<env>/
    ├── versions.tf        # required_version + required_providers (pinned)
    ├── backend.tf         # remote state config
    ├── providers.tf       # provider blocks, default_tags, aliases
    ├── variables.tf
    ├── locals.tf          # optional split
    ├── main.tf
    └── outputs.tf
```

Separate environments by **directory**, not workspace. Workspaces share backend config and one set of providers — they're a footgun for prod/stage isolation. Use them only for ephemeral parallel state (e.g. per-PR previews).

Resource and module names are `snake_case`. Don't repeat the resource type in the name (`aws_instance.web`, not `aws_instance.web_instance`). Use `main` when there's only one of something.

## Pin versions, commit the lock file

```hcl
terraform {
  required_version = ">= 1.10.0"   # or OpenTofu equivalent
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.31"
    }
  }
}
```

Always commit `.terraform.lock.hcl`. Run `tofu init -upgrade` to bump it deliberately. Modules omit provider `version =` (the calling environment pins it).

## Iteration and dynamic config

- **`for_each` over `count`** for any collection of distinct objects. `count` re-indexes on removal and destroys/recreates the wrong resource. Use `count` only for a true `0 or 1` toggle.
- **`dynamic` blocks** for repeated nested blocks (security group rules, tags, lifecycle hooks).
- **`for` expressions** and splats for transforming collections.
- **Object types with `optional()`** for structured inputs:
  ```hcl
  variable "buckets" {
    type = map(object({
      versioned = optional(bool, false)
      lifecycle_days = optional(number)
    }))
  }
  ```
- **OpenTofu 1.9+ provider `for_each`** for multi-region/multi-account fan-out without copy-pasted provider blocks. Not available in Terraform.

## Refactor without destroying

- **`moved` blocks** when renaming or restructuring resources/modules. Never edit state with `tofu state mv` if a `moved` block can express the change in code.
- **`import` blocks** (config-driven import) for adopting existing infra. Prefer over `tofu import` CLI — the block is reviewable, gets a plan, and can be removed after the next apply.
  ```hcl
  import {
    to = aws_s3_bucket.logs
    id = "my-logs-bucket"
  }
  ```
- **`removed` blocks** to drop a resource from state without destroying the real infrastructure (TF 1.7+, OpenTofu supported).

## Secrets, state, and ephemerality

Anything in state is sensitive — the backend must encrypt at rest, and access must be locked down. Beyond that, the two tools diverge:

- **OpenTofu**: use the built-in `terraform { encryption { ... } }` block to encrypt state and plan files end-to-end. No third party needed. Configure once in the environment.
- **Terraform**: use **ephemeral values / resources** (1.10+) and **write-only arguments** (1.11+) to keep secrets out of the plan and state file entirely. Read from a secrets manager via an `ephemeral` resource and pass it to a `write_only` argument; nothing persists.

Don't commit secrets to `*.tfvars`. Pass via env vars (`TF_VAR_*`), CI secret stores, or pull from a secrets manager at plan time.

## Backend and locking

Use a remote backend. For S3:

```hcl
terraform {
  backend "s3" {
    bucket       = "my-tf-state"
    key          = "env/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true   # native S3 locking — no DynamoDB needed (TF 1.10+, OpenTofu supported)
  }
}
```

Skip the `dynamodb_table` arg for new setups. Migrate existing setups with `use_lockfile = true` alongside the table, then remove the table once all callers are upgraded.

## Modules

- **Callers configure providers**, not modules. A module that hardcodes a `provider` block can't be reused across regions or accounts. Pass providers explicitly when needed (`providers = { aws = aws.us_east_1 }`).
- Don't over-modularize. A 3-resource module that's used once is just indirection — inline it. Extract a module when there are 3+ call sites or the boundary is genuinely meaningful (a "VPC", a "service").
- Pin module sources to a tag/sha for registry or git modules; never `ref=main`.

## Validation, preconditions, and checks

- **`variable "x" { validation { ... } }`** — multiple `validation` blocks per variable are supported. Validate at the boundary.
- **`lifecycle { precondition / postcondition }`** — guard a resource on assumptions about other inputs/outputs.
- **`check` blocks** (TF 1.5+, OpenTofu supported) — top-level assertions that emit warnings without halting apply. Use for drift/health checks, not hard invariants.

## Don't / Do

| Don't | Do |
|---|---|
| `count = length(var.items)` to iterate objects | `for_each = { for i in var.items : i.name => i }` |
| `template_file` data source | `templatefile("${path.module}/x.tpl", { ... })` |
| `null_resource` + `local-exec` for ordering | `terraform_data` (TF 1.4+, OpenTofu supported), or rethink — usually `depends_on` suffices |
| `tofu import` CLI for adoption | `import { to = ..., id = ... }` block |
| `tofu state mv` for renames | `moved { from = ..., to = ... }` block |
| DynamoDB lock table (new setup) | S3 backend `use_lockfile = true` |
| Workspaces for prod/stage | One directory per environment |
| Secrets in committed `*.tfvars` | OpenTofu state encryption / Terraform ephemeral + write-only / `TF_VAR_*` from CI |
| Wildcard provider versions (`>= 4.0`) | Pessimistic constraint (`~> 6.31`) + committed lock file |
| Hardcoded `provider` block inside a module | Provider configured by caller, passed in via `providers = { ... }` |

## Lifecycle gotchas

- `prevent_destroy = true` on stateful resources (databases, buckets with data, KMS keys).
- `create_before_destroy = true` on resources that can't have downtime during replacement (security groups attached to live instances, ASGs).
- `ignore_changes = [tags["LastModified"], ...]` for fields mutated out-of-band.

## Format, validate, lint

Always run before commit:

```sh
tofu fmt -recursive
tofu validate
tflint --recursive    # or trivy/checkov for security
```

`fmt` and `validate` are cheap and non-negotiable. `tflint` catches dead code, deprecated syntax, and provider-specific issues. Security scanners (`trivy config`, `checkov`) belong in CI. If the repo has `.tflint.hcl` or a pre-commit config, follow it.
