# State, backends, secrets

State is the file Terraform/OpenTofu writes after an apply that records "what got built." Every plan reads it, every apply writes it, and *everything sensitive your config touches ends up in it* — passwords, tokens, generated keys, all of it. State is therefore both an operational artifact (the source of truth for what's deployed) and a security artifact (a high-value target).

The most common AI failure mode here is treating state like a regular file: committing `terraform.tfstate` to git, running with a local backend on a shared module, using a DynamoDB lock table in 2026 when S3 has native locking, mocking out remote state with `terraform_remote_state` across stacks (couples lifecycles + lets stale outputs lie undetected), and leaving secrets in plaintext in state because "the bucket is private." Each of these is a security or correctness incident waiting to happen.

## Backends

A backend tells Terraform where to put state, how to lock it, and (sometimes) how to encrypt it. Every non-toy project needs a remote backend.

The four practical choices:

| Backend | When | Locking |
|---|---|---|
| `s3` | AWS-resident workloads | Native (`use_lockfile = true`, 1.10+) |
| `gcs` | GCP-resident workloads | Native (always on) |
| `azurerm` | Azure-resident workloads | Native (blob lease) |
| `http` | Self-hosted (Terraform Cloud, Scalr, Spacelift, custom) | Backend-defined |

Don't use `local`, `remote` (deprecated Cloud backend syntax), `consul`, `pg`, or `etcd` for new work.

### S3 backend, modern form

```hcl
terraform {
  backend "s3" {
    bucket       = "my-tf-state"
    key          = "env/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true                 # SSE-S3 at minimum; SSE-KMS preferred
    kms_key_id   = "arn:aws:kms:..."    # if you want KMS
    use_lockfile = true                 # native S3 locking (TF 1.10+, OpenTofu 1.10+)
  }
}
```

Key points:

- **`use_lockfile = true`** is the new way. Terraform writes a `.tflock` companion to the state object using S3's conditional writes (added 2024). No DynamoDB table, no IAM glue, no out-of-band lock cleanup.
- **`encrypt = true`** is non-negotiable; `kms_key_id` (with a customer-managed KMS key) is preferred over default SSE-S3 if your org has a key policy that supports it.
- **Bucket setup separately.** The S3 bucket holding state can't itself live in the state it manages. Bootstrap it once with a small one-off stack (or click-ops it in the first time).
- **Bucket hardening**: versioning ON (so you can recover from a corrupted apply), public-access block ON, replication if you want cross-region DR, lifecycle to expire old object versions after N days.

### Migrating off DynamoDB locks

If an existing setup uses `dynamodb_table = "tf-locks"`:

1. Bump everyone to TF 1.10+ or OpenTofu 1.10+.
2. Add `use_lockfile = true` **alongside** `dynamodb_table = ...`. During migration the backend will dual-lock.
3. Once every caller has been re-init'd, remove `dynamodb_table`. The next plan will reconfigure cleanly.
4. Delete the DynamoDB table when nothing reads it.

Don't skip step 2 → step 3 directly; you'll get a window where some clients lock via DynamoDB and others via the lockfile, defeating the purpose.

### Backend config can't interpolate

This is a perennial trap:

```hcl
# ❌ doesn't work — backend config is parsed before variables
terraform {
  backend "s3" {
    bucket = var.state_bucket
  }
}
```

Backend blocks are parsed before everything else, so variables/locals can't substitute. Three real options:

1. **Hardcode per-environment.** Each `environments/<env>/backend.tf` has its own concrete values. Best when you have a small number of environments. This is the default.
2. **Partial configuration + `-backend-config`.**
   ```hcl
   # backend.tf
   terraform {
     backend "s3" {}   # intentionally empty
   }
   ```
   Then `tofu init -backend-config=backend.hcl` (where `backend.hcl` is a key=value file, or pass `-backend-config="bucket=..."` flags). Use this when CI parameterizes the backend across N environments from one repo.
3. **Workspace prefixes for ephemeral state** (per-PR previews). Workspaces share a backend, so `key = "env/prod/terraform.tfstate"` becomes `env:/preview-123/terraform.tfstate` for each named workspace. Don't use this for prod/stage isolation — workspaces don't isolate providers, they only isolate state files.

## State encryption (OpenTofu only)

OpenTofu 1.10+ encrypts state and plan files end-to-end with a top-level `encryption {}` block. The state in the backend is ciphertext; only configured callers with the key can read it. This is **separate** from `encrypt = true` on the backend, which only does at-rest encryption of the storage layer.

```hcl
terraform {
  encryption {
    key_provider "aws_kms" "by_kms" {
      kms_key_id = "arn:aws:kms:us-east-1:111111111111:key/abc"
      region     = "us-east-1"
      key_spec   = "AES_256"
    }

    method "aes_gcm" "by_kms" {
      keys = key_provider.aws_kms.by_kms
    }

    state {
      method = method.aes_gcm.by_kms
      enforced = true
    }

    plan {
      method = method.aes_gcm.by_kms
      enforced = true
    }
  }
}
```

- **`enforced = true`** rejects any operation that would write unencrypted state. Always set it on prod.
- **Migration**: add the block without `enforced`, run one apply to encrypt existing state, then flip to `enforced = true`.
- **Key providers**: `aws_kms`, `gcp_kms`, `pbkdf2` (passphrase), or `openbao`/`vault`. Pick the one your org already has rotation policy around.
- **Rotation**: define a second key provider with `fallback`, switch encryption over to the new key, drop the fallback once everything's re-encrypted.

If you're on OpenTofu, **use this**. It's the cleanest answer to "secrets end up in state."

## Ephemeral values and write-only args (Terraform only)

Terraform 1.10 added **ephemeral resources** (values that exist only during plan/apply, never written to state). Terraform 1.11 added **write-only arguments** on managed resources (an argument value can be set but is never persisted in state). Together they let you pass secrets without leaving them in state.

```hcl
# 1) Pull secret with an ephemeral data source / resource — value is plan-time-only.
ephemeral "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/db/password"
}

# 2) Pass it to a write_only argument on a real resource.
resource "aws_db_instance" "main" {
  engine             = "postgres"
  instance_class     = "db.t4g.large"
  allocated_storage  = 50
  db_name            = "appdb"
  username           = "appadmin"
  password_wo        = ephemeral.aws_secretsmanager_secret_version.db_password.secret_string
  password_wo_version = 1   # bump to force re-read
}
```

- **`password_wo`** is the write-only counterpart to `password`. The resource accepts it but never persists.
- **`password_wo_version`** is required for any write-only arg; bumping it tells the provider to re-read the upstream value on next apply (since the value isn't in state to compare against).
- **Ephemeral resources/data sources** must be referenced only by other ephemeral things or by write-only args. They can't feed normal outputs (that would re-leak them).

This pattern is **Terraform-only** as of 2026 — OpenTofu's roadmap covers ephemerality but the user-facing block isn't shipped. On OpenTofu, use `encryption {}` (above) instead.

## Where to put secrets

In rough preference order:

1. **A secrets manager**, pulled at plan time via an ephemeral resource (Terraform) or `encryption {}`-protected state (OpenTofu) — `aws_secretsmanager_secret_version`, `aws_ssm_parameter` (with `WithDecryption`), `google_secret_manager_secret_version`, `vault_kv_secret_v2`.
2. **`TF_VAR_*` env vars from CI**, with the value pulled from the CI provider's secrets store. State still ends up containing the resource attributes derived from the secret, so combine with encryption.
3. **`*.tfvars` files passed via `-var-file=secrets.tfvars`**, gitignored, sourced from a secret store. Fine for local dev. **Never commit them.**
4. **Encrypted `.tfvars` via `sops`/`age`**, decrypted at the boundary. Workable, but `encryption {}` (OpenTofu) or ephemeral (Terraform) is cleaner if your version supports it.

**Never**:

- Commit `*.tfvars` with secret values to git.
- Pass a secret as a literal to `-var=password=...` on the CLI (lands in shell history).
- Store secrets in a Terraform variable with `default = "..."` and assume `sensitive = true` is enough — it hides the value from plan output, but state still contains it in plaintext.

## State surgery — last resort

Most things you might reach for `tofu state mv` / `tofu state rm` / `tofu import` for have a config-driven equivalent that's reviewable and applies through a normal plan. **Prefer those.**

| You want to… | Do this instead | Fall back to |
|---|---|---|
| Rename a resource | `moved { from = ..., to = ... }` block | `tofu state mv` |
| Adopt existing infra | `import { to = ..., id = "..." }` block | `tofu import` CLI |
| Stop managing without destroying | `removed { from = ..., lifecycle { destroy = false } }` | `tofu state rm` |
| Recover from a corrupted apply | restore previous state version from backend (S3 versioning) | hand-edit JSON |

See [patterns.md](patterns.md) for the block-driven forms. CLI state surgery is *fine*, just leaves no record in git, has no plan, and accumulates "we did this once, nobody knows why" entries.

When CLI state surgery is unavoidable:

- **Take a backup first**: `tofu state pull > state.backup.json` (or just rely on S3 versioning).
- **Acquire a lock**: same flow as any normal command; never run state surgery while another apply is in flight.
- **One command, one change.** Composing multiple `state mv`/`rm` commands into one script is how you lose state.

## Cross-stack data

When stack A needs an output from stack B, the options:

| Approach | When | Trade-off |
|---|---|---|
| **Provider-native data source** (e.g. `data "aws_vpc"`, `data "aws_ssm_parameter"`) | Whenever the value is queryable from the cloud | Cleanest — stack A reads cloud state, not Terraform state |
| **SSM Parameter / Secrets Manager as a pub/sub** | When you want explicit handoff | Stack B writes a parameter; stack A reads it. Decouples lifecycles. |
| **`terraform_remote_state` data source** | When the value isn't queryable any other way | Couples lifecycles; gives you stale outputs if you forget to apply B; requires read access to B's state. **Last resort.** |

`terraform_remote_state` is the easy answer that gets you in trouble — it's why two-stack designs end up with circular implicit dependencies and "I bumped A, why did B's plan change" surprises. Push values out via SSM/Secrets Manager when the boundary is real.

## Backend hardening checklist

For an S3 backend (adapt for GCS/AzureRM):

- [ ] Versioning ON
- [ ] Public access block ON (all four toggles)
- [ ] `encrypt = true` in backend config (SSE-KMS preferred)
- [ ] Bucket policy denies non-TLS access
- [ ] Bucket policy denies non-CMK-encrypted writes if using KMS
- [ ] IAM allows `tofu apply` runners and operators only; no `*` principals
- [ ] CloudTrail logging the bucket (separate trail or org-wide)
- [ ] Lifecycle rule to expire old versions after N days (e.g. 90)
- [ ] Replication to a second region if state loss = company-ending
- [ ] **State itself encrypted via `encryption {}`** (OpenTofu) or callers using **ephemeral + write-only** (Terraform)

## Don't / Do

| Don't | Do |
|---|---|
| Commit `terraform.tfstate` to git | Remote backend; commit only `.terraform.lock.hcl` |
| Local backend on a shared module | Remote backend with locking |
| DynamoDB lock table on new setups | `use_lockfile = true` on S3 backend |
| `var.X` inside a `backend "s3" {}` block | Partial config + `-backend-config=...` or hardcode per environment |
| `password = "literal"` in a `.tfvars` checked in | Secrets manager + ephemeral (TF) or `encryption {}` (OpenTofu) |
| `terraform_remote_state` across stacks by default | Provider-native data sources or SSM/Secrets Manager as a pub/sub |
| `tofu state mv` to rename | `moved {}` block |
| `tofu import` CLI for adoption | `import {}` block |
| `tofu state rm` to stop managing | `removed {}` block |
| State bucket without versioning | Versioning ON; lifecycle to expire after N days |
| Trust "the bucket is private" as the only secret defense | `encryption {}` (OpenTofu) or ephemeral (Terraform) layered on top |
