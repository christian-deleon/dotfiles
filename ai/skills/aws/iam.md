# IAM

IAM is two things stapled together: **identity** (who is calling) and **authorization** (what they can do). Both are policies. Most AWS security incidents trace back to one of three failures: long-lived access keys leaked, `Action: "*"` on `Resource: "*"`, or a trust policy that's too broad. New work should never have any of the three.

The mental model: **roles are the unit of identity** in AWS. Humans assume roles via Identity Center (SSO). CI assumes roles via OIDC. Workloads assume roles via instance profiles, Lambda execution roles, or IRSA / Pod Identity. IAM users with long-lived keys are a last-resort compatibility tool, not a default.

## Roles, not users

| Use | For |
|---|---|
| **IAM Identity Center** (formerly SSO) | Humans logging into AWS — console + CLI via `aws configure sso` |
| **OIDC federation** | CI/CD (GitHub Actions, GitLab, Buildkite) assumes a role with short-lived creds |
| **Instance profile** | EC2 — the instance assumes the role automatically |
| **Lambda execution role** | Lambda — the runtime assumes the role automatically |
| **IRSA / Pod Identity** | EKS pods — see [eks.md](eks.md) |
| **`AssumeRole`** | Cross-account / cross-service workloads |
| **IAM user + access key** | Last resort. Document why. Rotate every 90 days. |

If you find yourself creating an IAM user, stop and ask: can a role be assumed instead? The answer is almost always yes.

## Role naming

Follow the standard naming pattern from [naming.md](naming.md):

```
<env>-<app>-<purpose>

prod-checkout-api                  # role assumed by the checkout API service
prod-platform-ci-deploy            # role assumed by GitHub Actions deploying platform
prod-checkout-rds-monitoring       # service-specific role
```

Don't suffix `-role` (the ARN already says `:role/`). Don't include who created it. Don't include the principal that assumes it (that's encoded in the trust policy).

For paths, group by usage pattern, not by name:

```
arn:aws:iam::123456789012:role/service/prod-checkout-api
arn:aws:iam::123456789012:role/ci/prod-platform-deploy
arn:aws:iam::123456789012:role/human/admin
```

Paths are filterable in IAM API calls (`--path-prefix /ci/`) and make bulk policy operations easier.

## Trust policies — who can assume

The trust policy is the front door. Tighten it as much as the use case allows.

### EC2 instance profile

```hcl
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
```

### Lambda execution role

```hcl
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
```

### Cross-account `AssumeRole`

Require ExternalId (random string the caller must pass) and pin to a specific role ARN — never `root`:

```hcl
data "aws_iam_policy_document" "cross_account_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::222222222222:role/prod-platform-ci-deploy"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}
```

Don't trust the whole other account (`arn:aws:iam::222222222222:root`) unless you genuinely mean "any principal in that account". You almost never do.

### OIDC for GitHub Actions

The canonical pattern for CI — no long-lived keys, scoped per repo + branch:

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:my-org/my-repo:ref:refs/heads/main"]  # tight
    }
  }
}
```

Key rules:

- **Pin the `sub` claim.** `repo:my-org/my-repo:*` is too loose — anyone with a PR can assume it. Pin to a branch, environment, or tag pattern.
- **Pin `aud` to `sts.amazonaws.com`.** This is the audience GitHub uses; mismatched and the assume fails.
- **One OIDC provider per identity provider**, not per role. The provider is shared.

The OpenID Connect thumbprint changes when GitHub rotates its TLS cert. AWS now ignores the thumbprint for github.com OIDC, but the field is still required — the value above is the canonical one.

## Permission policies — what can be done

Three categories:

| Type | When |
|---|---|
| **AWS-managed policies** | Common patterns AWS maintains (`AWSLambdaBasicExecutionRole`, `AmazonS3ReadOnlyAccess`). Attach when they fit; never try to fork them. |
| **Customer-managed policies** | The default for app-specific permissions. Reusable across roles, version-controlled, shows up in policy simulator. |
| **Inline policies** | Use only when the policy is **tightly coupled** to one role and shouldn't be reused. Lifecycle ties to the role. |

Default to **customer-managed**. Inline policies are fine for one-off small permissions; AWS-managed are fine when the AWS-defined scope matches what you actually need.

### Minimum-viable policy pattern

```hcl
data "aws_iam_policy_document" "checkout_api" {
  # S3: read its own bucket
  statement {
    sid    = "ReadCheckoutAssets"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.assets.arn,
      "${aws_s3_bucket.assets.arn}/*",
    ]
  }

  # KMS: only the key that encrypts the bucket
  statement {
    sid    = "DecryptCheckoutAssets"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.checkout.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}
```

Rules:

- **Never `Action: "*"`** in a permission policy. Even for admin roles, prefer named services.
- **Never `Resource: "*"`** unless the action genuinely requires it (most `Describe*`/`List*` actions do; almost no `*:Create*`/`*:Update*`/`*:Delete*` actions do).
- **Pin to ARNs**, not name prefixes, when you control the resource. ARN is unambiguous; names can collide.
- **Use condition keys** (`kms:ViaService`, `aws:ResourceTag/<ns>:application`, `aws:SourceVpce`) to narrow access without redesigning the role.
- **`sid` is documentation.** Every statement gets a `sid` so CloudTrail and Access Analyzer findings are readable.

### Common condition keys worth knowing

| Key | Use |
|---|---|
| `aws:SourceIp` | Restrict to a CIDR range (office, VPN). Mind NAT — most workloads should use `aws:SourceVpc` or `aws:SourceVpce` instead. |
| `aws:SourceVpc` / `aws:SourceVpce` | Restrict S3/DynamoDB/etc. to a specific VPC or VPC endpoint |
| `aws:MultiFactorAuthPresent` | Require MFA for sensitive actions (delete, IAM changes) |
| `aws:ResourceTag/<key>` | Resource-based scoping by tag — common for "ops can touch nonprod" |
| `aws:RequestTag/<key>` | Require certain tags on resource creation |
| `aws:TagKeys` | Lock down which tag keys can be set |
| `aws:PrincipalOrgID` | Restrict to principals in your AWS Organization |
| `kms:ViaService` | Narrow KMS use to a specific service (S3, EBS, RDS, …) |

### Permissions boundaries

For developer-self-service patterns ("devs can create roles, but only ones that can do less than X"), set a **permissions boundary** on the roles they create. The boundary is the upper limit of what the bounded principal can do — even if their attached policies say more, the boundary caps them.

```hcl
resource "aws_iam_role" "dev_self_service" {
  name                 = "nonprod-platform-dev-self-service"
  assume_role_policy   = data.aws_iam_policy_document.dev_assume.json
  permissions_boundary = aws_iam_policy.dev_boundary.arn
}
```

The boundary policy itself uses `Allow` actions to define what's *possible*; if it doesn't `Allow` something, the bounded principal can't do it. Common shape: allow most service actions, but deny IAM/Org/Billing.

### Service Control Policies (SCPs)

Apply at the AWS Organizations level — they restrict what any principal in an account can do, regardless of IAM. Use them as a backstop, not the primary policy. Canonical SCPs to install in every account:

- Deny `iam:CreateUser` and `iam:CreateAccessKey` outside an allowlist (force roles).
- Deny disabling CloudTrail, GuardDuty, Config, Security Hub.
- Deny leaving the AWS Organization.
- Deny region usage outside the approved set (force `us-east-1` or whatever the org's choice is).

## What goes where

| Goal | Mechanism |
|---|---|
| "These IAM users should have admin in this account" | Identity Center + permission set |
| "GitHub Actions deploys this repo" | OIDC + role with deploy permissions |
| "EC2 instance writes to S3" | Instance profile + role with the S3 perms |
| "Pod in EKS writes to S3" | IRSA / Pod Identity — see [eks.md](eks.md) |
| "Lambda reads from DynamoDB" | Lambda execution role + DDB perms |
| "Cross-account audit logs read" | Role in account A with trust to account B, ExternalId required |
| "Dev sandbox can break things, but not real things" | Permissions boundary + SCP on the sandbox OU |

## Detection — Access Analyzer

Turn on **IAM Access Analyzer** in every account. It detects:

- Resources shared with external accounts (S3 buckets, IAM roles, KMS keys, Lambda, SQS).
- Unused IAM access — roles/permissions that haven't been used in the analyzer's lookback window.

Findings should be `0` or have a documented exception. Anything else is drift.

## Don't / Do

| Don't | Do |
|---|---|
| IAM user with long-lived `AKIA…` key | Role assumed via OIDC / Identity Center / instance profile |
| `Action: "*"`, `Resource: "*"` | Named actions on named resources; conditions for narrowing |
| `arn:aws:iam::<other-acct>:root` in trust policy | A specific role ARN + ExternalId |
| `repo:my-org/my-repo:*` in GitHub OIDC sub | Pin to branch (`:ref:refs/heads/main`), env (`:environment:prod`), or tag pattern |
| AWS-managed `AdministratorAccess` on everything | Identity Center permission set with the minimum needed |
| Inline policies as the default | Customer-managed policies; inline only for tight coupling |
| `-role` suffix on the role name | The ARN says `:role/`; no suffix |
| MFA optional on the IAM user that does have console access | MFA enforced via `aws:MultiFactorAuthPresent` in the policy |
| Same access key passed around the team | Identity Center, one identity per human |
| Forget to delete the role when the app is gone | Tag with `<ns>:application`; orphaned roles get cleaned in audits |
