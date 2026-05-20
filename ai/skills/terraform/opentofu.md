# OpenTofu vs Terraform

OpenTofu is the open-source fork of Terraform that emerged from the BSL relicensing in 2023. By 2026 the two have **mostly** kept in sync at the HCL/provider level — your modules work in both, the registry providers (AWS, GCP, Azure, etc.) work in both, `for_each` / `moved` / `import` / `removed` work in both. The fork has diverged on a small set of features that each side built independently after the split.

The most common AI failure mode here is assuming the two are interchangeable in all directions ("just s/tofu/terraform/g"). They're *mostly* interchangeable, but a handful of features exist only in one or the other and will silently fail or produce confusing errors if you migrate config without checking. This file is the cheat sheet for those.

The user's default is **OpenTofu** (`tofu` CLI). Terraform proper only appears at jobs where it's mandated. If you can't tell which is in use, see the detection table below.

## Quick orientation

|  | OpenTofu | Terraform |
|---|---|---|
| Maintainer | OpenTofu Foundation (Linux Foundation) | HashiCorp / IBM |
| License | MPL 2.0 (open source) | BSL 1.1 (source-available, non-compete) |
| CLI binary | `tofu` | `terraform` |
| Registry | OpenTofu Registry (Git-based, decentralized) | HashiCorp Registry |
| Lock file | `.terraform.lock.hcl` (compatible enough; two hash types) | `.terraform.lock.hcl` |
| File extensions | `*.tf` (primary), `*.tofu` (override, OpenTofu-only) | `*.tf` |
| State format | Same | Same |
| Provider compat | All major providers work in both | All major providers work in both |
| As of 2026 | 1.12.x | 1.13.x |

## What's the same

Almost everything that matters day-to-day:

- HCL syntax — every block, every expression, every function.
- All `for_each`, `count`, `dynamic`, `for`, splats, ternaries.
- `moved {}`, `import {}`, `removed {}`, `terraform_data`, `lifecycle`.
- `variable.validation` (single and multiple blocks), `precondition`/`postcondition`, `check {}`.
- `tofu test` / `terraform test`, `mock_provider`, `expect_failures`.
- S3/GCS/Azure backends with native locking.
- All HashiCorp-published providers (AWS, GCP, Azure, etc.).

If a feature is in the public docs of one and not the other, it's *probably* still there — the docs lag. But for the divergent features below, **assume they're not portable** until you verify.

## What's only in OpenTofu

### `encryption {}` block — state and plan encryption

```hcl
terraform {
  encryption {
    key_provider "aws_kms" "by_kms" {
      kms_key_id = "arn:aws:kms:..."
      region     = "us-east-1"
      key_spec   = "AES_256"
    }

    method "aes_gcm" "by_kms" {
      keys = key_provider.aws_kms.by_kms
    }

    state    { method = method.aes_gcm.by_kms ; enforced = true }
    plan     { method = method.aes_gcm.by_kms ; enforced = true }
  }
}
```

Encrypts state and plan files end-to-end at the application layer (separately from any backend at-rest encryption). See [state.md](state.md). **Terraform has no equivalent block** — for Terraform, use ephemeral resources + write-only arguments to keep secrets out of state.

### Provider `for_each`

```hcl
provider "aws" {
  for_each = toset(["us-east-1", "us-west-2", "eu-west-1"])
  alias    = "by_region"
  region   = each.key
}

resource "aws_s3_bucket" "regional_logs" {
  for_each = toset(["us-east-1", "us-west-2", "eu-west-1"])
  provider = aws.by_region[each.key]

  bucket = "logs-${each.key}"
}
```

Fan a single provider configuration across N regions/accounts without copy-pasted blocks. **Terraform doesn't support this** — for Terraform you write one `provider` block per alias, or generate them with code generation outside of Terraform.

### `-exclude` flag

```bash
tofu plan -exclude=module.expensive
tofu apply -exclude=aws_s3_bucket.legacy
```

Inverse of `-target`. Plan/apply everything *except* the listed addresses. Useful when one resource is broken and you want to apply everything else. Terraform has `-target` (which has many warnings about state divergence); OpenTofu has both `-target` and `-exclude`.

### Early variable evaluation

OpenTofu 1.8+ allows variables and locals in places Terraform doesn't, including the `backend` block, `source` field of modules, and `version` constraints:

```hcl
terraform {
  backend "s3" {
    bucket = var.state_bucket   # works in OpenTofu, not Terraform
    key    = "${var.environment}/terraform.tfstate"
    region = var.region
  }
}

module "vpc" {
  source = "git::ssh://git@github.com/${var.org}/tf-modules.git//vpc?ref=${var.module_version}"
  # ...
}
```

Terraform requires hardcoded backend config (or partial config + `-backend-config=...`) and hardcoded `source`/`version` in modules. This is the biggest day-to-day quality-of-life difference.

### `.tofu` override files

Any `*.tofu` file in a directory overrides the equivalent `*.tf` file at parse time, but **only for OpenTofu**. Terraform ignores `.tofu` files entirely.

```
main.tf       # parsed by both
main.tofu     # overrides main.tf, OpenTofu only
```

Use this when you want a config that mostly works in both but has OpenTofu-specific overrides (e.g. `encryption {}`) in a file that Terraform won't choke on.

### OpenTofu Registry

OpenTofu's registry is a *Git-based, decentralized* registry — providers and modules are discovered via a manifest in a GitHub repo, not a central server. `tofu` can pull from:

- OpenTofu Registry (default).
- HashiCorp Registry (via compat — still works).
- Direct Git URLs.
- OCI artifacts (1.8+).

Terraform pulls only from HashiCorp Registry and direct Git/OCI. If your `required_providers` references a provider that's only in the OpenTofu Registry, `terraform init` will fail.

In practice as of 2026, every major provider is in *both* registries. The divergence matters only at the margins.

## What's only in Terraform

### Ephemeral resources / values

```hcl
ephemeral "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/db/password"
}
```

A resource type whose values exist only during plan/apply, never written to state. Terraform 1.10+. **OpenTofu doesn't have this** — use `encryption {}` instead.

### Write-only arguments

```hcl
resource "aws_db_instance" "main" {
  password_wo         = ephemeral.aws_secretsmanager_secret_version.db_password.secret_string
  password_wo_version = 1
}
```

Arguments suffixed `_wo` accept a value but never persist it to state. Terraform 1.11+; **OpenTofu doesn't have these.**

### Cloud / Stacks / Sentinel / dynamic provider credentials

Anything in HashiCorp Cloud Platform — Terraform Cloud / Enterprise, the Stacks abstraction, Sentinel policy-as-code, dynamic provider credentials via workload identity — is a Terraform-only ecosystem. OpenTofu has its own counterparts (often via third parties: Scalr, Spacelift, env0) but no direct port.

If your config has `cloud {}` block, you're tied to Terraform. OpenTofu has no equivalent built-in cloud backend.

## Detecting which is in use

Heuristics, in rough order:

1. Run `tofu version` and `terraform version` — whichever exits 0 is on PATH.
2. Look for **OpenTofu-only signals** in the tree:
   - An `encryption {}` block in any `*.tf`.
   - A `provider "x" { for_each = ... }`.
   - A `*.tofu` file.
   - Variables/locals inside a `backend "..." {}` block.
3. Look for **Terraform-only signals**:
   - `cloud {}` block.
   - `ephemeral "..." {}` blocks.
   - `_wo` write-only arguments on resources.
   - A `terraform.tfbackend` file with Terraform Cloud config.
4. Check `.tflint.hcl` — `plugin "terraform"` runs in both, but `plugin "opentofu"` is OpenTofu-only.
5. Check CI workflows — `opentofu/setup-opentofu` vs `hashicorp/setup-terraform`.
6. Ask.

## Migration: Terraform → OpenTofu

For a config that has no Terraform-only features (the common case):

1. Install `tofu` (`tenv tofu install`).
2. Run `tofu init -upgrade` — it'll re-resolve providers against OpenTofu Registry (defaults to HashiCorp providers' MPL versions).
3. Run `tofu plan` — expect no changes.
4. If lock file diffs (different hash types), commit the new lock file.

That's typically it. Watch for:

- `cloud {}` blocks — needs replacement (Scalr/Spacelift/env0 backend, or migrate to direct S3 backend).
- Sentinel policies — port to OPA/Conftest.
- `ephemeral` blocks — port to OpenTofu `encryption {}` plus a different secrets pattern.
- Provider sources pinned to `registry.terraform.io/...` — these still work, but consider switching to the explicit short form (`hashicorp/aws`) which works in both.

## Migration: OpenTofu → Terraform

Harder, because OpenTofu has more new features:

1. Audit for OpenTofu-only constructs (the list above). Each needs a workaround:
   - `encryption {}` → secrets manager + ephemeral resources + write-only args.
   - `provider "x" { for_each = ... }` → expand to one `provider` block per alias.
   - `*.tofu` files → fold into `*.tf` or split the divergence into two configs.
   - Variables in `backend {}` → partial config + `-backend-config=...`.
2. Run `terraform init -upgrade`.
3. Run `terraform plan` — expect no resource changes (the underlying cloud doesn't care which CLI is running).
4. Commit the new lock file.

## Running both in CI

Common in libraries published to both registries. Matrix:

```yaml
strategy:
  matrix:
    impl:
      - { tool: tofu, version: '1.12.0', setup: opentofu/setup-opentofu@v1 }
      - { tool: terraform, version: '1.13.0', setup: hashicorp/setup-terraform@v3 }

steps:
  - uses: ${{ matrix.impl.setup }}
    with: { '${{ matrix.impl.tool }}_version': '${{ matrix.impl.version }}' }
  - run: ${{ matrix.impl.tool }} init -backend=false
  - run: ${{ matrix.impl.tool }} validate
  - run: ${{ matrix.impl.tool }} test
```

For consumer (non-library) repos, **pick one and stick with it.** Running both against the same state file is a recipe for confusion — the lock files diverge, the encryption blocks fail to parse on the wrong side, the test outputs differ subtly.

## Which to pick

| If you… | Use |
|---|---|
| Are starting fresh on a personal/open-source project | **OpenTofu** |
| Already pay for Terraform Cloud / Enterprise and use Sentinel + Stacks | **Terraform** |
| Want state encryption built in | **OpenTofu** |
| Want ephemeral values for secrets | **Terraform** (today) |
| Need provider `for_each` across many regions | **OpenTofu** |
| Have a compliance audit pinning you to "Terraform 1.x with BSL" | **Terraform** |
| Want variable interpolation in backend/source/version | **OpenTofu** |
| Work in an org that mandates HashiCorp products | **Terraform** |

In ambiguous cases for the user's own work: **OpenTofu**.

## Don't / Do

| Don't | Do |
|---|---|
| Assume any config "just works" across both | Audit for the divergent features in this file |
| Run both CLIs against the same state | Pick one per repo; matrix only for libraries |
| Translate `encryption {}` to Terraform by deleting the block | Replace with ephemeral + write-only on the Terraform side |
| Translate ephemeral resources to OpenTofu by removing them | Use `encryption {}` (different mechanism, similar outcome) |
| Use HashiCorp Registry-only providers without checking OpenTofu Registry availability | Verify provider availability in both registries before committing |
| Commit a lock file from one tool and re-init with the other | Re-init after switching; commit the regenerated lock |
| Mix `*.tofu` overrides with a Terraform-targeted repo | Either go all-in on OpenTofu or stick to `*.tf` only |
