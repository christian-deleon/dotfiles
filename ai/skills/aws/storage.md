# Storage

Three things, one mental model: **S3** is object storage (blobs, addressed by key, scoped to a bucket), **EBS** is block storage (a virtual disk attached to one EC2 instance), and **KMS** is the encryption layer that wraps both. Default to encrypted-everywhere with customer-managed keys per application — the cost is negligible and the audit story is one sentence.

The most common AI failure mode in storage: public S3 buckets, no versioning on data that needs it, "encryption is on" referring to AWS-owned keys instead of a CMK, EBS volumes that are `gp2` in 2026, and KMS keys with no rotation or no key policy at all.

## S3

### Bucket names

See [naming.md](naming.md). Recap of the S3-specific constraints:

- **63-char max**, globally unique across all of AWS.
- DNS-safe: lowercase, `[a-z0-9-]`, no underscores, no consecutive dots, no IP-shaped names.
- Don't use dots (`.`) unless you're explicitly serving content over a custom domain — dots break virtual-hosted-style HTTPS.
- Don't put account IDs in bucket names; they leak and are useless context.

Pattern:

```
<org>-<env>-<app>-<purpose>
checkout-prod-uploads
platform-prod-tofu-state
checkout-prod-uploads-7f3a       # short random suffix if the base name collides
```

### Required configuration for every bucket

Every new bucket gets these blocks. Treat them as non-negotiable defaults:

```hcl
resource "aws_s3_bucket" "this" {
  bucket = "checkout-prod-uploads"
}

# 1. Block public access — all four flags on
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. Encryption — SSE-KMS with a customer-managed key
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.checkout.arn
    }
    bucket_key_enabled = true   # cuts KMS request cost ~99% for bulk reads
  }
}

# 3. Versioning — on for data, off for logs/cache
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 4. Ownership — disable ACLs entirely
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 5. Lifecycle — expire abandoned multipart uploads and old versions
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-abandoned-multipart"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
```

That's the *floor*. Add storage class transitions, access logging, replication, etc. on top — they're additive.

### Versioning — when on, when off

| Bucket purpose | Versioning |
|---|---|
| User uploads, app data | **On** — accidental deletes happen |
| Static site / CDN origin | On (cheap insurance) |
| Tofu state | **On + MFA delete** if possible |
| Build artifacts you can rebuild | Off |
| Cache, transient outputs | Off |
| Logs (CloudTrail, ALB access logs) | Off — you'll never restore "the previous version of a log" |

When you turn versioning on, **always add a lifecycle rule** to expire noncurrent versions. Otherwise the bucket grows forever and the bill grows with it.

### Bucket policies vs ACLs

- **ACLs are deprecated.** `BucketOwnerEnforced` (block 4 above) turns them off entirely. Use it.
- **Bucket policies** are the way to grant cross-account / cross-service access. Always tighten with conditions.

Boilerplate for a bucket that only its app role and a specific other account can access:

```hcl
data "aws_iam_policy_document" "bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AppRoleAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.checkout_api.arn]
    }
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json
}
```

`DenyInsecureTransport` blocks any plaintext HTTP access — install it on every bucket, no exceptions.

### Storage classes

| Class | Use |
|---|---|
| `STANDARD` | Default, hot data |
| `INTELLIGENT_TIERING` | Anything with unpredictable access patterns — small monthly per-object monitoring fee, automatic tiering. **Set this as the default for app data.** |
| `STANDARD_IA` / `ONEZONE_IA` | Predictable cold data, only when you know access pattern |
| `GLACIER_IR` | Cold-ish, sub-second retrieval (instead of slower Glacier) |
| `GLACIER` / `DEEP_ARCHIVE` | Compliance archives, long retention with retrieval latency |

Intelligent-Tiering is the right default for any bucket where you don't know the access pattern. Don't try to predict — let it move objects.

### Access logging + CloudTrail data events

For sensitive buckets (PII, customer data, secrets), enable:

- **Server access logging** to a separate logs bucket (`<org>-<env>-platform-s3-logs`).
- **CloudTrail data events** for the bucket — captures object-level reads/writes.

Both cost money; turn them on selectively, not blanket.

### Replication

When you replicate cross-region or cross-account:

- Use **S3 Replication Time Control (RTC)** if SLA matters.
- Replicate **only what needs replicating** (filter by prefix or tag).
- KMS keys must exist in the destination region — `aws:kms` replication needs both keys present.

## EBS

### Volume types

| Type | Use | Notes |
|---|---|---|
| **`gp3`** | **Default for everything.** | 3000 IOPS / 125 MB/s baseline included; pay extra for more. Cheaper + faster than `gp2`. |
| `io2` / `io2 Block Express` | Sustained high IOPS (>16,000), low-latency DBs | Costlier; only when measured need |
| `st1` / `sc1` | Throughput-optimized HDD, cold HDD | Big sequential workloads (data lakes); rare |
| `gp2` | **Never for new work.** | Legacy; migrate to `gp3` on any volume you touch |

Default a root volume to `gp3`, 30 GB (or 50 GB if the AMI is larger), encrypted.

### Encryption — enable at the account level

In every account, every region, turn on **EBS Encryption by Default** with a customer-managed KMS key:

```hcl
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  key_arn = aws_kms_key.ebs.arn
}
```

After this, every new EBS volume — including those auto-created by AMIs, ASGs, RDS, etc. — is encrypted with your CMK whether the caller asked for it or not.

Snapshots inherit the encryption of the source volume. Copy across accounts/regions only works if both KMS keys grant access to the relevant principals.

### Snapshots and lifecycle

Use **Amazon Data Lifecycle Manager (DLM)** for snapshot schedules, not custom Lambdas:

```hcl
resource "aws_dlm_lifecycle_policy" "daily" {
  description        = "prod-daily-snapshots"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      "christian:backup" = "daily"
    }

    schedule {
      name = "Daily"
      create_rule { interval = 24, interval_unit = "HOURS", times = ["03:00"] }
      retain_rule { count = 14 }
      copy_tags = true
    }
  }
}
```

Tag volumes that need snapshots with `<ns>:backup = daily` (or `weekly`); DLM picks them up. Snapshots without retention pile up and outweigh the volume cost in months.

### Detaching / re-attaching

A volume is AZ-pinned — you can't attach it to an instance in a different AZ. To move a volume cross-AZ: snapshot, create a new volume in the target AZ from that snapshot.

## KMS

### Customer-managed key per application boundary

Default scope: **one CMK per `(env, application)`** boundary. Most app needs (S3 + EBS + Secrets Manager for the same app) ride that one key.

```hcl
resource "aws_kms_key" "checkout" {
  description             = "prod checkout app encryption"
  enable_key_rotation     = true                # always
  deletion_window_in_days = 30                  # leave room to recover

  policy = data.aws_iam_policy_document.checkout_key.json
}

resource "aws_kms_alias" "checkout" {
  name          = "alias/prod/checkout"
  target_key_id = aws_kms_key.checkout.key_id
}
```

Aliases give the key a human name (see [naming.md](naming.md) — `alias/<env>/<app>[/<purpose>]`). Always reference the **alias** in app config, the **ARN** in IAM policies.

### Key policy — the root of access

Unlike most resources, KMS keys require their own resource policy. **If the key policy doesn't grant access, no IAM policy can.**

```hcl
data "aws_iam_policy_document" "checkout_key" {
  # The account itself can manage the key (so IAM policies work normally)
  statement {
    sid    = "EnableIAMPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # The app role can use the key (encrypt/decrypt only — no admin)
  statement {
    sid    = "AppRoleUse"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.checkout_api.arn]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}
```

The "enable IAM permissions" statement is the standard pattern — it delegates to IAM. Without it, you have to enumerate every principal in the key policy itself.

### Rotation

`enable_key_rotation = true` rotates the underlying key material every year, transparently — old ciphertext still decrypts. There is no reason not to enable it. Imported key material has separate handling.

### Per-service vs shared keys

| Need a separate CMK | Why |
|---|---|
| Hard data classification boundary (PII vs non-PII) | One key per class; policy separately auditable |
| Cross-account access | Each granted account needs key-policy entries — keep blast radius small |
| Compliance / customer key per tenant | When the contract requires it |

| Reuse the same CMK | Why |
|---|---|
| Same app, multiple AWS services (S3 + EBS + Secrets) | Audit story is "the checkout key" |
| All non-PII data in one application | Per-service keys add ops, not security |

### AWS-managed keys (`aws/s3`, `aws/ebs`, etc.)

Free-tier "encryption-at-rest" is AWS-managed keys. They're better than nothing but:

- You can't change the key policy.
- You can't audit usage independently of "all of S3 encryption did stuff".
- Cross-account access is impossible.

Use them only for transient / sandbox workloads where the CMK overhead isn't worth it. Production gets a CMK.

### KMS pricing — beware the per-request line

KMS costs $1/key/month and $0.03 per 10,000 API calls. The request cost dominates for high-throughput workloads (every S3 PUT/GET with SSE-KMS is a KMS call, every EBS read goes through KMS). Two mitigations:

- **S3 bucket keys** (`bucket_key_enabled = true`) — cuts KMS calls by ~99% for bulk reads/writes.
- **Avoid per-object KMS calls in tight loops** — use a long-lived data key (`GenerateDataKey` once, reuse the plaintext).

## Don't / Do

| Don't | Do |
|---|---|
| `block_public_access` flags set to false | All four `true`, every bucket |
| Bucket without versioning where data matters | Versioning on + lifecycle expiring noncurrent versions |
| `aws:kms` without specifying `kms_master_key_id` | Always specify the CMK ARN |
| `bucket_key_enabled = false` for high-throughput buckets | `true` — slashes KMS request cost |
| Tofu state in an unencrypted, unversioned bucket | Encrypted + versioned + MFA delete if possible |
| `gp2` for a new EBS volume | `gp3` |
| EBS encryption left default-off in a new account | `aws_ebs_encryption_by_default` + `aws_ebs_default_kms_key` |
| Hand-roll a snapshot cron in Lambda | DLM with a tag-targeted policy |
| KMS key with no rotation | `enable_key_rotation = true` |
| KMS key alias `alias/checkout-key` | `alias/<env>/<app>` |
| `aws/s3` AWS-managed key in production | CMK per app boundary |
| Pass plaintext bucket policies via the console | `aws_s3_bucket_policy` + `aws_iam_policy_document` |
| Forget `DenyInsecureTransport` | Bake it into every bucket policy |
