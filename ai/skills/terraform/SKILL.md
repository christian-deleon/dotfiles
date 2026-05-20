---
name: terraform
description: Modern Terraform / OpenTofu authoring (HCL). ALWAYS use when editing `*.tf`, `*.tofu`, `terraform.tfvars`, `.terraform.lock.hcl`, files under `terraform/` or `environments/` trees, or for prompts mentioning Terraform, OpenTofu, HCL, providers, modules, state, `terraform apply`/`plan`, `tofu` CLI, or 'add a resource', 'fix the variable', 'update the module', 'plan this', 'write a test'. Default to `tofu` in examples (the user's primary tool); call out features that exist only in Terraform or only in OpenTofu. Opinionated stack — `tofu` for everything new, S3 backend with native locking, `for_each` over `count`, `moved`/`import`/`removed` blocks over CLI state surgery, OpenTofu state encryption (or Terraform ephemeral + write-only) for secrets, `tofu test` for module verification, `tflint` + `trivy config` in CI.
compatibility: opencode
---

# Terraform / OpenTofu

Terraform and OpenTofu share the same HCL language and >95% of features. Treat them as one tool whose two implementations have *diverged on a few specific axes* (state encryption, provider `for_each`, the `-exclude` flag, early variable evaluation, registry source). The user's default is **OpenTofu** (`tofu` CLI); Terraform proper only appears at jobs where it's mandated. Use `tofu` in examples — commands are identical for `terraform` unless explicitly noted.

The most common AI failure mode here is writing 2020-era Terraform: `count = length(...)` on lists of objects, DynamoDB lock tables, `null_resource` + `local-exec` for ordering, `template_file` data sources, `tofu state mv` for renames, hardcoded `provider` blocks inside modules, secrets in `*.tfvars`, workspaces for prod/stage isolation, wildcard provider versions, and the dreaded `terraform import` CLI dance instead of an `import {}` block. Don't do any of that. The defaults below are non-negotiable for new code.

If you can't tell which implementation is in use, check for: a `tofu` binary on PATH, a `.tofu` override file in the tree, an `encryption {}` block (OpenTofu-only), a `provider "x" { for_each = ... }` (OpenTofu-only), a `pylock.toml`-style `.terraform.lock.hcl` from `terraform.io` registry sources (Terraform). Otherwise ask.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Design a module, pass providers, pick a source (registry/git/local), version it | [modules.md](modules.md) |
| Configure a backend, set up locking, encrypt state, handle secrets, do state surgery | [state.md](state.md) |
| Write iteration (`for_each`/`dynamic`/`for`), refactor without destroy (`moved`/`import`/`removed`), tune lifecycle | [patterns.md](patterns.md) |
| Write a `tofu test` run, add variable validation, precondition/postcondition, `check` blocks | [testing.md](testing.md) |
| Set up fmt/validate, `tflint`, security scanners, pre-commit, CI, `terraform-docs` | [tooling.md](tooling.md) |
| Decide between Terraform and OpenTofu, use a OpenTofu-only feature, migrate from one to the other | [opentofu.md](opentofu.md) |

For one-off edits, the cheat sheets in this file are usually enough. Reach for the reference files when the task warrants depth.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Implementation | **OpenTofu** (`tofu`) | Terraform 1.12+ at work when mandated; commands are identical otherwise |
| Version pin | `required_version = ">= 1.10.0"` (Terraform) or `">= 1.9.0"` (OpenTofu) | Bump as features need it; pin lower bound, not exact |
| Backend | **S3 with `use_lockfile = true`** | No DynamoDB. GCS/AzureRM/HTTP equivalents are fine |
| State encryption | **OpenTofu `encryption {}` block** (preferred) or **Terraform ephemeral + write-only** | Never plaintext secrets in state; never `*.tfvars` with secrets in git |
| Provider versions | Pessimistic constraint (`~> 6.31`) + committed lock | Update with `tofu init -upgrade`, deliberately |
| Iteration | **`for_each`** over `count` | `count` only for `0 or 1` toggles |
| Refactors | **`moved {}`** + **`import {}`** + **`removed {}`** blocks | Never `tofu state mv` / `tofu import` CLI for anything reviewable |
| Validation | `variable.validation`, `lifecycle.precondition`/`postcondition`, top-level `check` | Boundary checks at variables, invariants at resources, drift at `check` |
| Tests | **`tofu test`** runs in `tests/*.tftest.hcl` | Plan-based assertions; `command = apply` only when you mean it |
| Format / lint / scan | `tofu fmt -recursive` + `tofu validate` + `tflint` + `trivy config` | All non-negotiable in CI |
| Docs | `terraform-docs` | Auto-generate `README.md` per module from `variables.tf`/`outputs.tf` |

## Project layout

Separate environments by **directory**, not workspace. Workspaces share one backend config and one set of providers — they're a footgun for prod/stage isolation. Use them only for ephemeral parallel state (per-PR previews).

```
terraform/
├── modules/
│   └── <module_name>/
│       ├── versions.tf       # required_providers (NO version pin — caller controls)
│       ├── variables.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── README.md         # generated by terraform-docs
│       └── tests/
│           └── basic.tftest.hcl
└── environments/<cloud>/<env>/
    ├── versions.tf           # required_version + required_providers (pinned)
    ├── backend.tf            # remote state config
    ├── providers.tf          # provider blocks, default_tags, aliases
    ├── variables.tf
    ├── locals.tf             # optional split
    ├── main.tf
    └── outputs.tf
```

Resource and module names are `snake_case`. Don't repeat the resource type in the name (`aws_instance.web`, not `aws_instance.web_instance`). Use `main` when there's only one of something. Module instance names describe the *role*, not the *type* (`module.bastion`, not `module.ec2_instance`).

See [modules.md](modules.md) for when to split a module vs inline, and how to layer environments → composition root → modules.

## Pin versions, commit the lock file

```hcl
# environments/aws/prod/versions.tf
terraform {
  required_version = ">= 1.10.0"   # or ">= 1.9.0" for tofu
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.31"
    }
  }
}
```

Always commit `.terraform.lock.hcl`. Run `tofu init -upgrade` to bump it deliberately. Modules **omit** provider `version =` — the calling environment pins it. Wildcards (`>= 4.0`) on a provider are a bug; the lock file is what should pin the exact resolution.

OpenTofu's lock file defaults to two hashes (`h1:` and `zh:`); Terraform's is `h1:`-only. The files are interoperable enough for most cases but not bit-identical. See [opentofu.md](opentofu.md) for the full diff.

## Modern syntax cheat sheet

| Use | Don't use |
|---|---|
| `for_each = { for i in var.items : i.name => i }` | `count = length(var.items)` over objects |
| `dynamic "ingress" { for_each = var.rules; content { ... } }` | repeated nested blocks |
| `templatefile("${path.module}/x.tpl", { ... })` | `template_file` data source |
| `terraform_data` resource (1.4+) | `null_resource` |
| `moved { from = ..., to = ... }` block | `tofu state mv` |
| `import { to = ..., id = "..." }` block | `tofu import` CLI |
| `removed { from = ..., lifecycle { destroy = false } }` | `tofu state rm` for adoption-out |
| `optional(bool, false)` in object types | nested ternaries for default-on-missing |
| `validation { condition = ..., error_message = ... }` (multiple per variable) | runtime crashes on bad inputs |
| `ephemeral` resources / `write_only` args (Terraform 1.10+/1.11+) | plaintext secrets in state |
| `encryption {}` top-level block (OpenTofu 1.10+) | `sops`-encrypted tfstate hacks |
| `provider "aws" { for_each = ... }` (OpenTofu 1.9+) | copy-pasted provider blocks per region |
| `use_lockfile = true` on S3 backend | `dynamodb_table = ...` lock table |
| `tofu test` with `*.tftest.hcl` | hand-rolled plan-parsers in shell |
| `terraform { backend "s3" { region = var.region } }` not allowed → use partial config + `-backend-config` | trying to interpolate into the backend block |

Splats (`aws_instance.web[*].id`) and `for` expressions handle most collection transforms. Reach for `dynamic` only when you literally need a nested block repeated.

## Universal rules

1. **`for_each` over `count`** for any collection of distinct objects. `count` re-indexes on removal and destroys/recreates the wrong resource. Use `count` only for `0 or 1` toggles.
2. **One directory per environment.** No workspaces for prod/stage. Compose environments out of modules.
3. **Modules don't configure providers** — callers do. A module that hardcodes a `provider {}` block can't be reused across regions or accounts.
4. **Pin provider versions with `~>` and commit the lock file.** Bump deliberately via `tofu init -upgrade`.
5. **Refactor in code, not in state.** `moved {}` over `tofu state mv`; `import {}` over `tofu import` CLI; `removed {}` over `tofu state rm`. State surgery only when a block genuinely can't express it.
6. **Never put secrets in `*.tfvars` committed to git.** Use OpenTofu `encryption {}`, Terraform `ephemeral` + `write_only`, `TF_VAR_*` from CI, or a secrets-manager data source at plan time. See [state.md](state.md).
7. **Validate at the boundary.** Multiple `validation {}` blocks per variable (TF 1.9+/OpenTofu supported). Push errors up to where someone *typed* the wrong thing, not down to where it eventually crashes.
8. **`prevent_destroy = true`** on stateful resources (databases, buckets with data, KMS keys). **`create_before_destroy = true`** on resources that can't have downtime during replacement.
9. **Run `tofu fmt -recursive` + `tofu validate` + `tflint` before commit.** All three. None of them are optional. Security scanners (`trivy config`, `checkov`) belong in CI.
10. **Write a `tofu test` run for every module that gets reused.** Even a trivial `command = plan` run catches 80% of the regressions you'd otherwise eat in `apply`.

## Implementation-agnostic patterns

The body of every reference file in this skill is written for "the user's setup" — `tofu` by default. When a feature is *only* available in one implementation, it's called out with **(Terraform only)** or **(OpenTofu only)**. When a feature exists in both but the syntax differs, the OpenTofu form is shown first.

## Don't / Do (top-level)

| Don't | Do |
|---|---|
| Workspaces for prod/stage isolation | One directory per environment |
| `count = length(var.items)` over distinct objects | `for_each = { for i in var.items : i.name => i }` |
| `template_file` data source | `templatefile("${path.module}/x.tpl", { ... })` |
| `null_resource` + `local-exec` for ordering | `terraform_data` (or rethink — usually `depends_on` suffices) |
| `tofu import` CLI for adoption | `import { to = ..., id = ... }` block |
| `tofu state mv` for renames | `moved { from = ..., to = ... }` block |
| `tofu state rm` to stop managing | `removed { from = ..., lifecycle { destroy = false } }` |
| DynamoDB lock table (new setup) | S3 backend `use_lockfile = true` |
| Wildcard provider versions (`>= 4.0`) | Pessimistic constraint (`~> 6.31`) + committed lock |
| Hardcoded `provider {}` inside a module | Provider configured by caller, passed via `providers = { aws = aws.us_east_1 }` |
| Secrets in committed `*.tfvars` | OpenTofu `encryption {}` / Terraform `ephemeral` + `write_only` / `TF_VAR_*` from CI |
| `terraform_remote_state` for cross-stack data | Provider-native data sources (e.g. `aws_ssm_parameter`) where possible — `remote_state` couples lifecycles |
| Mega-modules that do "the platform" | Small, composable modules; composition root in the environment |
| Module sources with `ref=main` | `ref=v1.4.0` or a commit SHA |
| Skipping `tofu fmt`/`validate`/`tflint` | Run all three before every commit |

## After you change anything in this skill

Run `dot install` to refresh the symlinks across all three tools. No restart needed.
