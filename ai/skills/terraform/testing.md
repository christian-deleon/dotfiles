# Testing

Terraform tests aren't unit tests in the Java/Python sense — they're **plan-based assertions and (optionally) full apply-then-destroy lifecycles**. The point isn't to catch logic bugs in the runtime; it's to catch *config bugs* before they reach an environment. Did the module accept this input? Did it produce the expected outputs? Did the variable validation fire? Did `for_each` key the resources stably?

The most common AI failure mode is over-testing apply paths against real clouds (slow, expensive, flaky) **or** under-testing the plan paths that catch 80% of real bugs for free. The right shape: every module has at least one `command = plan` run; you reach for `command = apply` only when a resource has interesting post-create behavior that plan can't surface.

`tofu test` (and the identical `terraform test`) shipped in TF 1.6, matured in 1.7–1.10. It's good enough that Terratest, kitchen-terraform, and shell-based plan-parsers are mostly legacy.

## File layout and where tests live

```
modules/vpc/
├── main.tf
├── variables.tf
├── outputs.tf
└── tests/
    ├── basic.tftest.hcl
    ├── multi_az.tftest.hcl
    └── validation.tftest.hcl
```

Test files have the extension `.tftest.hcl` (or `.tftest.json`). They live in `tests/` by convention; `tofu test` discovers them anywhere under the working directory. You run them with:

```bash
tofu test                    # all tests in the current module
tofu test -filter=tests/basic.tftest.hcl
tofu test -verbose           # show plan/apply output for each run
```

## Anatomy of a test file

```hcl
# tests/basic.tftest.hcl

variables {
  # defaults applied to every run unless overridden
  name        = "test-vpc"
  cidr_block  = "10.0.0.0/16"
}

run "plan_succeeds" {
  command = plan

  assert {
    condition     = output.vpc_id != null
    error_message = "vpc_id output should be set after plan"
  }
}

run "with_two_subnets" {
  command = plan

  variables {
    subnets = {
      a = { cidr_block = "10.0.1.0/24", availability_zone = "us-east-1a" }
      b = { cidr_block = "10.0.2.0/24", availability_zone = "us-east-1b" }
    }
  }

  assert {
    condition     = length(aws_subnet.this) == 2
    error_message = "expected 2 subnets, got ${length(aws_subnet.this)}"
  }

  assert {
    condition     = aws_subnet.this["a"].cidr_block == "10.0.1.0/24"
    error_message = "subnet 'a' has wrong CIDR"
  }
}

run "invalid_name_fails" {
  command = plan

  variables {
    name = "INVALID UPPERCASE NAME"
  }

  expect_failures = [
    var.name,
  ]
}
```

The shape:

- **`variables {}` at the top** sets defaults for every `run` block in the file. Each `run` can override per-test.
- **`run "<name>"`** is one assertion suite. Name describes what's being tested.
- **`command = plan`** is the default and what you want most of the time. It runs `tofu plan` against the module with the given variables.
- **`command = apply`** runs the full lifecycle — `apply`, then `destroy` on teardown. Use only when you need post-apply values to assert on. Costs real cloud calls.
- **`assert { condition = ..., error_message = ... }`** is the unit of validation. Conditions are HCL expressions evaluated in the planned/applied state — reference resources by their address, outputs by `output.<name>`, variables by `var.<name>`.
- **`expect_failures = [var.name, resource.x.y]`** asserts that a specific input or resource *should* have raised an error during plan/apply. Use to test `validation {}` blocks and `precondition`/`postcondition`.

## Plan vs apply mode

| `command = plan` | `command = apply` |
|---|---|
| No cloud changes — uses provider plan semantics only | Real `apply` + `destroy` on teardown |
| Fast (seconds per run) | Slow (minutes; depends on the resources) |
| Catches: config errors, validation failures, missing required args, `for_each` keying, output shape, planned resource counts, plan diffs against fixtures | Catches: provider quirks at apply time, dynamic values that resolve only after creation (auto-assigned IDs, computed attributes), cross-resource consistency |
| 90% of useful module tests | The 10% where plan isn't enough |

Default to plan. Add an apply-mode test when you genuinely need a post-create attribute. For modules with no apply-mode tests, run `tofu test` in CI on every PR; for modules with apply-mode tests, gate them behind an explicit `-filter` so the cheap suite still runs on every push.

## Mocking providers

For pure-logic modules (no real cloud), mock the provider so `apply` is free:

```hcl
# tests/basic.tftest.hcl

mock_provider "aws" {
  # by default, all resources are mocked with synthetic values
}

run "with_mocks" {
  command = apply   # safe — mocked

  assert {
    condition     = length(aws_subnet.this) == 2
    error_message = "..."
  }
}
```

For finer control, mock individual resources:

```hcl
mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
}
```

Mocks let you run `command = apply` paths without real cloud — great for asserting on attributes that only exist post-apply (`arn`, `id`, etc.). Trade-off: you're trusting the mock to match reality. Keep at least one real-cloud integration test in CI nightly to catch drift.

## `override_resource` and `override_data` — per-test overrides

When most tests use real providers but one test needs to mock just one resource:

```hcl
run "with_overridden_caller_identity" {
  command = plan

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "999999999999"
    }
  }

  assert {
    condition     = local.account_id == "999999999999"
    error_message = "..."
  }
}
```

Use this when you want to test branching behavior that depends on a data source value, without actually hitting the cloud for that one data source.

## Testing variable validation

```hcl
run "cidr_too_small" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/30"
  }

  expect_failures = [
    var.cidr_block,
  ]
}
```

The test passes if and only if `var.cidr_block`'s `validation {}` block fired. This is the right way to verify boundary checks. Without `expect_failures`, the test fails when validation fires (the plan errored). With it, you've inverted the assertion.

`expect_failures` accepts:

- Variables: `var.<name>`
- Resource preconditions/postconditions: `aws_db_instance.main`
- Data source preconditions/postconditions: `data.aws_ami.main`
- Output preconditions: `output.<name>`

## Helpers and fixtures

For shared setup across many runs, use a separate module:

```hcl
# tests/setup/main.tf
resource "random_pet" "name" {
  length = 2
}

output "name" {
  value = "test-${random_pet.name.id}"
}
```

```hcl
# tests/basic.tftest.hcl
run "setup" {
  module {
    source = "./tests/setup"
  }
}

run "main" {
  command = plan

  variables {
    name = run.setup.name
  }

  assert { ... }
}
```

`run.setup.name` references the output of the earlier setup run. The setup run executes once per `tofu test` invocation; subsequent runs reuse its state.

## Provider configuration in tests

If your tests need a specific provider config (e.g. region):

```hcl
# tests/basic.tftest.hcl

provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true
  access_key                  = "mock"
  secret_key                  = "mock"
}

run "plan_succeeds" {
  command = plan
  ...
}
```

For pure plan-mode tests against mocked providers, `skip_credentials_validation = true` lets you run without real AWS credentials — useful in CI for forked PRs.

## Variable validation, preconditions, postconditions, checks — a tour

These four mechanisms catch different things at different times:

| Mechanism | Where | Runs when | Halts on failure? |
|---|---|---|---|
| `variable.validation` | At the boundary (variable declaration) | Plan — before resources are processed | Yes |
| `lifecycle.precondition` | Inside a resource | Plan — before the resource is planned | Yes |
| `lifecycle.postcondition` | Inside a resource | Apply — after the resource exists | Yes |
| `output.precondition` | Inside an output | Plan / apply — when the output is computed | Yes |
| Top-level `check {}` | Module root | Plan and apply | No (warns only) |

Rule of thumb:

- **Bad input** → `variable.validation`. The error message points at the variable.
- **Conditional assumption on another input/output** → `precondition` on the resource that would otherwise misbehave. Example: "this module requires `var.engine == "postgres"`."
- **Cloud returned something unexpected** → `postcondition`. Example: "the AMI we got has the expected architecture."
- **Drift / health** → `check {}`. Example: "the endpoint returns 200." Warns, doesn't block.

```hcl
variable "instance_count" {
  type = number

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "instance_count must be 1–10"
  }
}

resource "aws_instance" "web" {
  count = var.instance_count

  ami           = data.aws_ami.al2023.id
  instance_type = "t3.small"

  lifecycle {
    precondition {
      condition     = data.aws_ami.al2023.architecture == "x86_64"
      error_message = "AL2023 AMI must be x86_64 in this stack"
    }

    postcondition {
      condition     = self.public_ip != ""
      error_message = "instance should have a public IP"
    }
  }
}

check "endpoint_reachable" {
  data "http" "health" {
    url = "http://${aws_instance.web[0].public_ip}/"
  }

  assert {
    condition     = data.http.health.status_code == 200
    error_message = "health endpoint returned ${data.http.health.status_code}"
  }
}
```

## When `tofu test` isn't enough

You still reach for an external test framework when:

- **Cross-stack integration**. `tofu test` tests one module/root at a time. Testing "stack A's output flows to stack B" is better expressed in shell or `pytest` with `tftest`/`pytest-terraform` helpers.
- **Behavior assertions after apply**: "after applying the EKS module, does `kubectl get nodes` succeed?" That's a wrapper test — Terratest (Go), or `pytest` calling `tofu apply` and then making real HTTP/k8s calls.
- **Policy as code**: Sentinel (Terraform Cloud), OPA/Conftest, or `terraform-compliance`. These test plan JSON against organizational policies — "no S3 bucket may be public," "every RDS must have backups." Different layer than module behavior.
- **Compliance / security scanning**: `trivy config`, `checkov`, `tfsec` (now part of trivy). Run in CI, not as test suite. See [tooling.md](tooling.md).

## CI integration

Minimal recipe:

```yaml
# .github/workflows/terraform.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - run: tofu fmt -check -recursive
      - run: tofu init -backend=false
        working-directory: modules/vpc
      - run: tofu validate
        working-directory: modules/vpc
      - run: tofu test
        working-directory: modules/vpc
```

Notes:

- `tofu init -backend=false` skips backend init — fine for tests because they use mocked or local state.
- Run `fmt -check` separately so a fmt failure doesn't mask a test failure.
- For matrix testing across Terraform/OpenTofu versions: parallel jobs with `setup-terraform` and `setup-opentofu`.

## Don't / Do

| Don't | Do |
|---|---|
| Skip module tests entirely | At least one `run "plan_succeeds"` per reusable module |
| `command = apply` everywhere | `plan` by default; `apply` only when post-apply values matter |
| Real cloud calls in unit tests | `mock_provider` (free, deterministic); keep one real-cloud integration test nightly |
| Hand-rolled shell scripts that parse `tofu plan -json` | `tofu test` with `assert {}` |
| Test that a variable accepts bad input by hoping the cloud rejects it | `expect_failures = [var.x]` against the `validation {}` block |
| `check {}` for hard invariants | `precondition`/`postcondition` for hard; `check` warns only |
| `tofu test` against the production backend | Tests get their own state (in-memory or local); never the real one |
| Bundle Terratest with every module | Reserve external frameworks for cross-stack or post-apply behavior |
