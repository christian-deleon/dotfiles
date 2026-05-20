# HCL patterns

Most "is this idiomatic Terraform?" judgments come down to a handful of patterns: how you iterate (`for_each` vs `count`), how you transform data (`for` expressions and splats), how you handle conditional nested blocks (`dynamic`), how you evolve state without destroying things (`moved` / `import` / `removed`), and how you tune lifecycle. This file collects all of those.

The most common AI failure mode here is reaching for the older form because the LLM saw 100k lines of it in training data: `count = length(var.items)` over a list of objects, `null_resource` for ordering, `template_file` data sources, `tofu state mv` for renames, three-deep ternaries to handle defaults. Every one of these has a current-decade replacement; the table at the bottom is the full catalog.

## `for_each` vs `count`

**`for_each` is the default.** Use `count` only as a `0 or 1` toggle.

The trap with `count`: removing an element from the middle of a list re-indexes everything after it, and Terraform sees `aws_instance.web[1]` as a *different* resource than the one that was there before. Result: it destroys and recreates the wrong instance. `for_each` keys by map key (string), so removing one element only affects the one whose key disappeared.

### `for_each` over a map

```hcl
variable "users" {
  type = map(object({
    role  = string
    email = string
  }))
  default = {
    alice = { role = "admin",  email = "alice@example.com" }
    bob   = { role = "viewer", email = "bob@example.com" }
  }
}

resource "aws_iam_user" "users" {
  for_each = var.users

  name = each.key
  tags = {
    Email = each.value.email
    Role  = each.value.role
  }
}
```

Access individual instances by key: `aws_iam_user.users["alice"]`.

### `for_each` over a list of objects

Convert to a map first with `for`:

```hcl
variable "subnets" {
  type = list(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))
}

resource "aws_subnet" "this" {
  for_each = { for s in var.subnets : s.name => s }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = { Name = each.key }
}
```

The map key needs to be **known at plan time** (so resource addresses are stable) and **unique**. `s.name` is usually right; `s.id` works if your input gives IDs.

### `for_each` over a set of strings

```hcl
resource "aws_route53_record" "domains" {
  for_each = toset(var.domain_names)

  zone_id = aws_route53_zone.main.zone_id
  name    = each.key
  type    = "A"
  ...
}
```

`toset()` is the convention when the elements *are* the keys.

### When `count` is correct

```hcl
resource "aws_eip" "nat" {
  count  = var.create_nat ? 1 : 0
  domain = "vpc"
}
```

Pure on/off toggle, single resource, no risk of "the second element disappearing." Reference as `aws_eip.nat[0]` and check `length(aws_eip.nat) > 0` if you might consume it from a place where it could be absent.

`count` is also fine when you genuinely want N indistinguishable copies (`count = 3` for three identical workers). That's rare in practice — you usually want a `for_each` over a map of named workers.

## `dynamic` blocks

Use `dynamic` when a nested block needs to repeat based on input:

```hcl
resource "aws_security_group" "web" {
  name   = "web"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from
      to_port     = ingress.value.to
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }
}
```

The block label inside `dynamic "ingress" {` becomes the iterator name (`ingress.key`, `ingress.value`). Rename it with `iterator = rule` if you want clarity in nested dynamics.

**Don't use `dynamic` for a single nested block.** If `for_each = var.cors_enabled ? [1] : []` is how you toggle one block on/off, that's a code smell — the block was meant to be omitted entirely, not conditionally present. Reach for an `optional()` field on an input object instead, or split into two resources.

## `for` expressions and splats

`for` expressions transform collections without writing imperative loops:

```hcl
# list comprehension
locals {
  user_emails = [for u in var.users : u.email]
}

# with filter
locals {
  admin_emails = [for u in var.users : u.email if u.role == "admin"]
}

# list to map (also the for_each conversion idiom)
locals {
  users_by_name = { for u in var.users : u.name => u }
}

# nested objects
locals {
  subnet_cidrs = { for k, v in var.subnets : k => v.cidr_block }
}
```

Splats are shorthand for `[for x in list : x.attr]`:

```hcl
# splat
aws_instance.web[*].id

# equivalent for-expression
[for i in aws_instance.web : i.id]
```

Splat works on `count`-style lists (`web[*]`) **and** `for_each` maps (`values(aws_instance.web)[*].id`, or `[for i in aws_instance.web : i.id]`).

## Object types with `optional()`

The 1.3+ `optional(type, default)` is the right tool for "some fields have sensible defaults":

```hcl
variable "buckets" {
  type = map(object({
    versioning     = optional(bool, false)
    encryption     = optional(string, "AES256")  # AES256 | aws:kms
    lifecycle_days = optional(number)            # null when omitted
    tags           = optional(map(string), {})
  }))
}
```

Callers can omit any optional field; the default kicks in. `optional()` without a default means "may be omitted, value is `null`." Avoid nested ternaries (`var.x.lifecycle != null ? var.x.lifecycle : 30`) — that pattern predates `optional()` and is now just noise.

## `templatefile` over `template_file`

```hcl
resource "aws_iam_role_policy" "task" {
  name   = "ecs-task"
  role   = aws_iam_role.task.name
  policy = templatefile("${path.module}/task-policy.json.tpl", {
    bucket_arn = aws_s3_bucket.uploads.arn
  })
}
```

The `template_file` data source has been deprecated since 0.12. Use `templatefile(path, vars)` instead. Template files are normal text with `${var}` interpolation; for control flow use `%{ if ... }` / `%{ for ... }` directives:

```hcl
# policy.json.tpl
{
  "Version": "2012-10-17",
  "Statement": [
%{ for arn in bucket_arns ~}
    { "Effect": "Allow", "Action": "s3:GetObject", "Resource": "${arn}/*" }%{ if arn != bucket_arns[length(bucket_arns) - 1] },%{ endif }
%{ endfor ~}
  ]
}
```

For JSON specifically, prefer `jsonencode({ ... })` over a template — it handles quoting and commas automatically:

```hcl
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
    for arn in var.bucket_arns : {
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${arn}/*"
    }
  ]
})
```

## `moved {}` blocks — rename without destroy

When you rename a resource in code, Terraform sees a "remove A, create B" by default and destroys the old one. A `moved {}` block migrates state instead:

```hcl
# old:
# resource "aws_instance" "web" { ... }

# new:
resource "aws_instance" "bastion" { ... }

moved {
  from = aws_instance.web
  to   = aws_instance.bastion
}
```

Run a plan — you'll see `moved` operations queued, no destroy/create. After the next apply, the `moved {}` block has done its job and you can delete it (or leave it for posterity; it's a no-op if applied a second time).

`moved {}` handles:

- Renames: `aws_instance.web` → `aws_instance.bastion`
- Module moves: `module.network.aws_vpc.main` → `module.vpc.aws_vpc.main`
- Index changes: `aws_instance.web[0]` → `aws_instance.web["primary"]` (count → for_each migration)

It does **not** handle moves *across* state files (different backends/environments) — you still need `tofu state mv` with state pull/push for that.

## `import {}` blocks — adopt existing infra

```hcl
import {
  to = aws_s3_bucket.logs
  id = "company-logs-prod"
}

resource "aws_s3_bucket" "logs" {
  bucket = "company-logs-prod"
  # configure to match what's there
}
```

The block:

1. Shows up in the plan as "import + any configuration drift."
2. Imports on apply.
3. Can be deleted after the import succeeds (or left — re-applying is a no-op).

The block-driven form is reviewable, gets a real plan diff, and works in CI without out-of-band `tofu import` shell commands. **Always prefer it over the CLI.**

For mass imports (adopting an existing account), `tofu plan -generate-config-out=generated.tf` will scaffold resource blocks from the cloud — you write only the `import {}` blocks; the resource bodies get generated. The generated config is messy and you'll want to clean it up before committing, but it's a massive head start.

## `removed {}` blocks — stop managing

To drop a resource from state without destroying the real infrastructure (e.g. you're handing it off to another team / stack):

```hcl
removed {
  from = aws_s3_bucket.legacy

  lifecycle {
    destroy = false
  }
}
```

After apply, Terraform forgets the bucket exists; the bucket itself is untouched. Use this when transferring ownership across stacks. **Don't** use it to "clean up state" when the resource actually still exists in your config — just delete the resource block in that case.

If `destroy = true` (the default for `removed`), the resource *is* destroyed on apply. Be careful which one you want.

## Lifecycle arguments

```hcl
resource "aws_db_instance" "main" {
  # ...

  lifecycle {
    prevent_destroy       = true
    create_before_destroy = false
    ignore_changes        = [tags["LastModified"], password]
    replace_triggered_by  = [aws_security_group.db.id]

    precondition {
      condition     = var.engine == "postgres"
      error_message = "This stack only supports Postgres."
    }

    postcondition {
      condition     = self.engine_version != ""
      error_message = "engine_version must resolve after apply."
    }
  }
}
```

| Arg | Use |
|---|---|
| `prevent_destroy = true` | Stateful resources: databases, buckets with data, KMS keys, anything whose loss is unrecoverable. Forces a code change before `tofu apply` will delete the resource. |
| `create_before_destroy = true` | Resources that can't have downtime during replacement: security groups attached to live instances, load balancer listeners, ASGs. **Counter-intuitive but critical**: order resources you can't replace in-place into a create-before-destroy chain or apply will fail. |
| `ignore_changes = [...]` | Fields modified out-of-band (autoscaling target capacity, tags appended by other systems, password rotations). List the specific attributes; never `ignore_changes = all`. |
| `replace_triggered_by = [...]` | Force replacement when an unrelated resource changes (e.g. recreate ASG when launch template version changes). |
| `precondition {}` | Guard before this resource is created/updated. Multiple blocks allowed. Use for "this only works under conditions X." |
| `postcondition {}` | Assert after the resource exists. Use for "verify the cloud returned a value we expected." |

`prevent_destroy` is the one people skip and regret. Add it to every stateful resource you create. If you genuinely need to destroy it later, delete the line, apply, then delete the resource — two steps, intentional.

## `terraform_data` replaces `null_resource`

For "I need a resource that holds a value and triggers re-creation on change":

```hcl
resource "terraform_data" "image_id" {
  input = var.image_id

  triggers_replace = [
    var.image_id,
  ]
}

resource "aws_instance" "web" {
  ami = terraform_data.image_id.output
  # ...
}
```

`terraform_data` is built in (1.4+) — no `null` provider dependency, no `local-exec` baggage. Use it when:

- You want to pin a derived value that triggers cascading replacements when it changes.
- You need a `triggers_replace` semantic outside any specific resource.

For "I need to run a shell command on apply" — **stop and rethink**. `local-exec` is almost always the wrong answer; it makes the apply non-deterministic, breaks idempotency, and doesn't fit in remote-apply runners. Patterns to reach for first:

- A real provider for the thing the script is doing.
- A data source that queries the state you wanted to compute.
- An out-of-band CI step that runs *after* apply, against apply outputs.

If after all that you still need `local-exec`, attach it to `terraform_data` (not `null_resource`), keep the command idempotent, and document why.

## `depends_on` hygiene

`depends_on` should be rare. Most dependencies are implicit through attribute references (`x.id = y.id` → `x` depends on `y`). Reach for `depends_on` only when:

- The dependency is real but invisible (e.g. an IAM role policy must exist *before* the resource that assumes the role, even though no attribute is referenced).
- A provider has eventual-consistency quirks (e.g. an AWS API that returns OK before the resource is actually queryable).

```hcl
resource "aws_lambda_function" "fn" {
  function_name = "my-fn"
  role          = aws_iam_role.fn.arn
  # ...

  depends_on = [
    aws_iam_role_policy_attachment.fn,  # must attach the policy before lambda runs
  ]
}
```

**Never** `depends_on` an entire module unless you really mean "wait for everything in there." That's almost always a sign the module should be split.

## Variable validation

Push errors to where someone *typed* the wrong thing. Multiple `validation {}` blocks per variable are supported (TF 1.9+, OpenTofu 1.8+):

```hcl
variable "engine_version" {
  type = string

  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must match 16.x"
  }

  validation {
    condition     = !contains(["16.0", "16.1"], var.engine_version)
    error_message = "engine_version 16.0 and 16.1 have a known bug; use 16.2+"
  }
}
```

`validation` runs at plan time and can reference *other variables* (since TF 1.9 / OpenTofu 1.8) — useful for cross-field invariants. Validate aggressively; the error message at validation time is way more useful than a cloud provider's API error 20 minutes into apply.

## `check {}` — drift and health

Top-level `check` blocks emit warnings without halting apply. Use them for things that *should* be true but you don't want to block on:

```hcl
data "http" "endpoint" {
  url = "https://${aws_lb.main.dns_name}/health"
}

check "health" {
  data "http" "endpoint" {
    url = "https://${aws_lb.main.dns_name}/health"
  }

  assert {
    condition     = data.http.endpoint.status_code == 200
    error_message = "Health check returned ${data.http.endpoint.status_code}"
  }
}
```

`check` is for "monitor, don't fail" — drift detection, post-apply health probes, asserting that another team's stack still has the resource you depend on. For hard invariants, use `precondition`/`postcondition` instead.

## Don't / Do (HCL patterns)

| Don't | Do |
|---|---|
| `count = length(var.items)` over distinct objects | `for_each = { for i in var.items : i.name => i }` |
| `count = var.x ? 1 : 0` then complex `[0]` indexing | `for_each` with `{}` or `{ key = obj }` |
| `dynamic` block toggled by `for_each = enabled ? [1] : []` | Split into two resources, or use `optional()` on the input |
| `null_resource` + `local-exec` for ordering | `terraform_data` + `depends_on`; usually `depends_on` alone suffices |
| `template_file` data source | `templatefile("${path.module}/x.tpl", { ... })` |
| String-concat to build JSON | `jsonencode({ ... })` with `for` inside |
| Three-deep ternaries to default missing fields | `optional(type, default)` inside an object type |
| `tofu state mv` to rename | `moved { from = ..., to = ... }` |
| `tofu import` CLI | `import { to = ..., id = "..." }` block |
| `tofu state rm` to stop managing | `removed { from = ..., lifecycle { destroy = false } }` |
| `ignore_changes = all` | Specific attributes only |
| Missing `prevent_destroy` on stateful resources | `prevent_destroy = true` on databases, buckets with data, KMS keys |
| `depends_on = [module.foo]` | Identify the specific resource(s) inside the module that need to come first; or refactor |
| Catching errors at the cloud API | `validation {}` on the variable that holds the bad value |
| `check {}` for hard invariants | `precondition`/`postcondition` for hard; `check` for warn-only |
