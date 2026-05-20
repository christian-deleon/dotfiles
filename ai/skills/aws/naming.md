# Naming

**Names identify; tags describe.** A name is a short, human-readable identifier that someone reads in the console, in `aws` CLI output, in alarms, and in CloudTrail. Anything that belongs in metadata (env, owner, cost center, data class) goes in **tags**, not the name. The most common mistake is treating the name as a structured database key — it isn't, it's a label.

## Hard rules

- **Don't repeat the resource type in the name.** A security group is already a security group — don't call it `web-sg` or `app-securitygroup`. Same for `-bucket`, `-instance`, `-role`, `-lambda`, `-queue`, `-table`, `-cluster`. The ARN, console, and provider already say what kind of thing it is.
- **kebab-case, lowercase, alphanumeric + hyphens only.** No underscores, no camelCase, no PascalCase, no spaces.
- **Start and end with a letter or number.** No leading/trailing/double hyphens.
- **No PII, no AWS account IDs, no secrets** in names.
- **Stable identifiers.** A name shouldn't have to change when the resource is migrated, scaled, or replatformed. If you're tempted to bake an instance type or region into the name, stop — those are tags.

## Default pattern

```
<env>-<app>-<purpose>[-<qualifier>]
```

| Example | Notes |
|---|---|
| `prod-checkout-api` | App + purpose, no resource type |
| `prod-checkout-api-blue` | Qualifier for blue/green |
| `prod-checkout-redis` | Purpose is "redis" — not `redis-cluster` |
| `nonprod-shared-egress` | Cross-app shared resource gets `shared` as `<app>` |
| `sandbox-platform-bastion` | Environment-app-purpose |

Use **purpose**, not type. `prod-checkout-redis` (purpose: cache for checkout) beats `prod-checkout-redis-cluster` (cluster is redundant — ElastiCache calls it a cluster regardless).

### Environments

| Value | Use for |
|---|---|
| `prod` | Production, customer-facing |
| `nonprod` | Anything pre-prod that mirrors prod shape (staging, qa, uat) |
| `sandbox` | Personal/team scratch; safe to delete |
| `dev` | Long-lived shared dev — only if `nonprod` is reserved |

Avoid splitting `nonprod` into `staging`/`qa`/`uat` at the name level — that's a tag (`<ns>:tier`). Names should not multiply.

## Per-resource constraints

AWS resource name limits vary widely. Check before composing long names.

| Resource | Max name | Extra rules |
|---|---|---|
| S3 bucket | 63 chars | DNS-safe: lowercase, no underscores, no consecutive dots, no IP-shaped names |
| IAM role / user / policy / group | 64 chars | Path is separate (`/<path>/<name>`) |
| Lambda function | 64 chars | Alias names also 64 chars |
| RDS DB instance identifier | 63 chars | Must start with a letter |
| RDS cluster identifier | 63 chars | Same |
| CloudWatch log group | 512 chars | Slashes OK — use `/aws/lambda/<name>` shape for Lambda |
| ECS cluster / service / task family | 255 chars | Family name + revision is the identity |
| EKS cluster | 100 chars | DNS-safe label rules apply |
| SQS queue | 80 chars | `.fifo` suffix required for FIFO queues |
| SNS topic | 256 chars | `.fifo` suffix required for FIFO |
| ElastiCache cluster | 50 chars | Different from RDS — much shorter |
| Security group name | 255 chars | Names are not unique across VPCs — IDs are |
| EC2 instance | (Name tag, 255 chars) | EC2 has no "name", the `Name` tag is the convention |
| DynamoDB table | 255 chars | |
| KMS key alias | 256 chars after `alias/` | Must start with `alias/` |

### Length traps

If a long pattern won't fit, abbreviate the **environment** before abbreviating the application — application identity is what humans search by:

| Full | Squeezed |
|---|---|
| `prod`, `nonprod`, `sandbox` | `p`, `np`, `sb` |
| `production-checkout-payments-webhook` | `p-checkout-payments-webhook` |

Don't abbreviate `<app>` or `<purpose>` — they're the searchable parts.

## Per-resource quirks

### S3 buckets

Bucket names are globally unique across **all AWS accounts**. Two safe patterns:

```
<org>-<env>-<app>-<purpose>         # most common
checkout-prod-uploads-7f3a          # short suffix when the basic name collides
```

Tack on a short random suffix (4–6 hex) if the basic name clashes. Don't put account IDs in bucket names — they leak, and the bucket is already in your account.

Don't use dots (`.`) in bucket names unless you're explicitly serving static content from a custom domain — dots break virtual-hosted-style URLs over HTTPS.

### IAM roles

The path (`/<path>/<name>`) and name are separate fields. Use paths to group, not to name:

```
arn:aws:iam::123456789012:role/service/prod-checkout-api
                                  ^path^  ^name^
```

The `name` follows the standard `<env>-<app>-<purpose>` pattern; the path is optional and used for batch operations (e.g. `--path-prefix /service/`).

Don't append `-role` to the name — the ARN already says `:role/`.

### Lambda functions

Lambda names show up in CloudWatch log group names as `/aws/lambda/<function-name>`. Keep them readable:

```
prod-checkout-stripe-webhook        # good
prod-checkout-lambda-stripe-fn      # bad — both "lambda" and "fn" are redundant
```

### Security groups

SG **names** are not unique across a VPC, only across `(VPC, name)` pairs. Avoid relying on the name as an identifier — use the `id` output of the resource. But still **name** the SG by purpose:

```
prod-checkout-api          # SG attached to the checkout API
prod-checkout-redis        # SG attached to checkout's Redis
```

Not `prod-checkout-api-sg`. Not `prod-checkout-app-securitygroup`.

### EC2 instances

EC2 has no `name` field — the convention is the `Name` tag. Stamp it via `default_tags` augmented per-resource, or via a tag block in `aws_instance`:

```hcl
resource "aws_instance" "api" {
  # ...
  tags = {
    Name = "prod-checkout-api"
  }
}
```

The capital-N `Name` tag is the one the console renders as the instance name — `name` (lowercase) is not.

### CloudWatch log groups

Mirror the resource that produces the logs:

```
/aws/lambda/prod-checkout-stripe-webhook       # Lambda — required shape
/ecs/prod-checkout-api                          # ECS task logs
/eks/prod-platform/cluster                      # EKS control plane logs
/app/prod-checkout-api                          # custom app logs
```

Slashes are allowed and conventional.

### KMS keys

Keys have a UUID identity. Use **aliases** as the human-readable name:

```
alias/<env>/<app>
alias/<env>/<app>/<purpose>     # if one app needs multiple CMKs

alias/prod/checkout
alias/prod/checkout/snapshots
```

The path-style alias makes batch listing/grouping easier in the console.

## Don't / Do

| Don't | Do |
|---|---|
| `web-sg`, `app-bucket`, `auth-lambda` | `web`, `app-assets`, `auth` |
| `ProdCheckoutApi`, `prod_checkout_api` | `prod-checkout-api` |
| `acct-123456789012-logs` | `prod-platform-logs` (account ID is implicit) |
| `prod-checkout-api-us-east-1` (region in name) | tag with `<ns>:region` if needed |
| `prod-checkout-api-t3medium` (size in name) | size is implicit / changes — leave it out |
| `prod-checkout-api-v2` (version in name) | new app = new app, otherwise tag with `<ns>:version` |
| `christian-test-bucket` | name still follows the pattern even for personal — `sandbox-christian-scratch` |
| `MyTeam-Prod-Checkout-API` | `prod-checkout-api` |
