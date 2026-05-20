# Tooling

Terraform's tooling story is small but every piece is non-negotiable. The core loop — `fmt`, `validate`, `tflint`, security scanner, `terraform-docs`, `tofu test` — runs on every PR and every commit. If any of these aren't wired into CI, the whole repo is at the mercy of whoever's most disciplined.

The most common AI failure mode here is treating tooling as polish — "I'll add tflint later" — and accumulating drift that's painful to fix in one shot. Add the full set on day one of a repo; the per-PR cost is tiny and the cleanup cost is exponential.

## The toolchain at a glance

| Tool | Purpose | Where |
|---|---|---|
| `tofu fmt` / `terraform fmt` | Canonical formatting | Local pre-commit + CI |
| `tofu validate` | Syntax + schema | Local + CI |
| `tflint` | Linting, dead code, deprecated patterns, provider rules | Local + CI |
| `trivy config` (or `checkov`) | Security/compliance scanning | CI; optionally local |
| `terraform-docs` | Auto-generated `README.md` per module | Pre-commit or CI |
| `tofu test` | Module behavior tests | CI |
| `pre-commit` | Local hook orchestration | Optional but recommended |
| `tfenv` / `tenv` | Manage multiple TF/OpenTofu versions | Local only |

## `tofu fmt` — formatting

Idempotent. Run it. Always.

```bash
tofu fmt -recursive              # rewrite every *.tf under cwd
tofu fmt -check -recursive       # exit non-zero if anything needs formatting (CI)
tofu fmt -diff -recursive        # show what would change
```

There are no formatting preferences worth bikeshedding. `tofu fmt` is the rule.

`terraform fmt` is identical (same parser). They produce bit-identical output on shared HCL features.

## `tofu validate` — syntax + provider schema

```bash
tofu init -backend=false   # download providers without configuring backend
tofu validate              # parse + schema-check
```

`validate` doesn't talk to the cloud. It does:

- Parse every `.tf` file.
- Resolve references between resources/modules/variables.
- Check argument names/types against provider schemas (which is why you need `init` first to download providers).

It **doesn't** catch:

- Logic errors (`for_each = { ... }` with wrong keys).
- Runtime values (anything that depends on cloud API responses).
- Multi-stack issues (cross-environment, cross-state).

For those, you need `plan`, `test`, or a security scanner.

CI flow:

```bash
tofu init -backend=false
tofu fmt -check -recursive
tofu validate
tflint
trivy config .
tofu test
```

`init -backend=false` is the trick — you skip configuring the remote backend (so no auth needed for `validate`) but still get providers, which is all `validate` needs.

## `tflint` — linting

`tflint` is what catches deprecated syntax, dead code, unused variables, naming-convention violations, and provider-specific anti-patterns. It's a separate binary; install via `tofu`-aware package managers or `tflint -install` for plugins.

### Minimal `.tflint.hcl`

```hcl
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  call_module_type = "all"   # also lint child modules
  format           = "compact"
}
```

The `terraform` ruleset (built in) covers HCL idioms — required variable types, missing descriptions, deprecated syntax, untyped variables, etc.

The provider-specific rulesets (`aws`, `google`, `azurerm`) catch:

- Invalid instance types (`t9.foo`).
- Deprecated AMI IDs / data sources.
- IAM policies that grant `*`.
- Missing required tags.

Install plugins with `tflint --init`. Add the plugin to `.tflint.hcl` first, then run `--init` to download.

### Per-module vs per-repo

Run `tflint` from the repo root with `call_module_type = "all"` to lint every reachable module — that's the right default. For monorepos with many independent environments, `tflint --recursive` walks subdirectories independently.

```bash
tflint --recursive --format compact
```

### Don't disable lints repo-wide

Lint failures are signal. If a rule is firing across the codebase, fix the codebase, not the rule. Exceptions go inline with a comment explaining why:

```hcl
# tflint-ignore: terraform_unused_declarations
variable "deprecated_input" {
  type    = string
  default = ""
}
```

Repo-wide `disabled_by_default = true` in `.tflint.hcl` defeats the point.

## Security scanning — `trivy config` (or `checkov`)

Both scan Terraform/OpenTofu config against a database of CIS, AWS-Foundations, SOC2-style rules: "S3 bucket has public access," "RDS instance has no encryption," "security group allows 0.0.0.0/0 on port 22."

`trivy` (formerly `tfsec` — Aqua merged tfsec into Trivy) is the modern default:

```bash
trivy config --severity HIGH,CRITICAL .
trivy config --misconfig-scanners terraform .
trivy config --skip-dirs '.terraform' --skip-files '*.tfstate' .
```

`checkov` is the heavier alternative — broader rule coverage, more frameworks (also scans CloudFormation, K8s, Helm, Dockerfile, etc.), Python-based.

```bash
checkov -d . --framework terraform
checkov -d . --framework terraform --skip-check CKV_AWS_19,CKV_AWS_20
```

Pick one per repo. Running both produces duplicate findings with different IDs.

### Where they belong

- **CI, gating PRs.** Pin to a minimum severity threshold (`HIGH` for trivy, `MEDIUM` for checkov) and fail the build on findings.
- **Not pre-commit** unless the suite is small enough — these are slow.
- **Suppression**: inline comments (`#trivy:ignore:AVD-AWS-...`) or `.trivyignore` / `.checkov.yml`. **Always include a reason and an expiry date** for suppressions; otherwise they pile up.

### What scanners can't catch

Both tools catch *config-level* issues. They don't:

- Read runtime cloud state ("is this bucket *actually* public").
- Detect cross-stack issues ("this IAM role can assume that role").
- Replace policy-as-code (Sentinel, OPA/Conftest) when the policy is org-specific.

For drift detection, run `tofu plan` on a schedule. For policy-as-code, layer Sentinel/OPA *on top* of the security scanner.

## `terraform-docs` — README generation

```bash
terraform-docs markdown table --output-file README.md --output-mode inject ./
```

Generates a section into `README.md` describing the module's inputs/outputs/resources/providers, between marker comments:

```markdown
<!-- BEGIN_TF_DOCS -->
...auto-generated...
<!-- END_TF_DOCS -->
```

Add a `.terraform-docs.yml` per module (or one at the repo root):

```yaml
formatter: markdown table
output:
  file: README.md
  mode: inject
sort:
  enabled: true
  by: name
settings:
  anchor: true
  default: true
  required: true
  type: true
```

Run as a pre-commit hook so READMEs never drift from the actual `variables.tf`/`outputs.tf`. If the README is out of sync in code review, that's a process problem worth fixing.

## `pre-commit` — wiring it all locally

`pre-commit` (the Python tool, `pre-commit-framework`) hooks all of the above into git so they run on every commit.

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
      - id: terraform_trivy
      - id: terraform_docs
        args:
          - --args=--config=.terraform-docs.yml
```

Install: `pre-commit install`. Now every `git commit` runs the full suite on staged `.tf` files. Skip with `git commit --no-verify` only when there's a genuine emergency — usually that's a sign the hook is configured wrong, not that the hook is wrong.

The same config is the basis for CI: most CI providers can install pre-commit and run `pre-commit run --all-files` on PRs.

## Managing Terraform/OpenTofu versions

Don't `apt install terraform` or `brew install opentofu` for project work — pin per-repo.

| Tool | Use |
|---|---|
| `tenv` | Universal version manager — handles Terraform, OpenTofu, Terragrunt, Atmos. Reads `.terraform-version` / `.opentofu-version`. **Current default.** |
| `tfenv` | Terraform-only, predates `tenv`. Still works, less actively maintained. |
| `asdf` | Generalist; fine if you already use it for other languages |

```bash
echo "1.12.0" > .opentofu-version   # pin OpenTofu version
tenv tofu install                   # install if missing
tenv use tofu                       # set as active for this shell
```

Commit `.opentofu-version` (or `.terraform-version`). CI uses the same file via `setup-opentofu@v1` / `setup-terraform@v3`.

## Terragrunt / Atmos / Spacelift / Atlantis

These are *orchestration* tools layered on top of Terraform/OpenTofu — they don't replace it.

- **Terragrunt**: DRY across many environments via `terragrunt.hcl` configs. Generates `terraform.tfvars` and `backend.tf` from one source. Adds remote state config inheritance, plan-all/apply-all, and dependency graphs. Use when you have 10+ environments that share 95% of config. The cost: another layer to understand and debug. For 1–3 environments, just duplicate `backend.tf` and `provider.tf` — Terragrunt is overkill.
- **Atmos** (Cloudposse): similar to Terragrunt, but YAML-driven and more opinionated. Strongest in monorepos with a "stack" abstraction (env × tenant × region).
- **Spacelift** / **Atlantis** / **Env0**: PR-driven apply orchestration. They run `plan` on PRs, comment the diff, and run `apply` on merge with approval gates. Use when humans clicking "apply" on a CI button is the right level of control.

None of these change the HCL inside your modules — they just orchestrate *how* the modules get applied across many environments. Reach for them when manual `cd environments/aws/prod && tofu apply` becomes unmanageable, not before.

## CI patterns

Minimum useful CI for a Terraform repo:

```yaml
# .github/workflows/terraform.yml
name: terraform

on:
  pull_request:
    paths: ['**/*.tf', '**/*.tofu', '.tflint.hcl']

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: '1.12.0'
      - run: tofu fmt -check -recursive
      - uses: terraform-linters/setup-tflint@v4
      - run: tflint --init
      - run: tflint --recursive --format compact
      - uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          severity: 'HIGH,CRITICAL'
          exit-code: '1'

  validate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        dir:
          - environments/aws/prod
          - environments/aws/stage
          - modules/vpc
          - modules/cluster
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - run: tofu init -backend=false
        working-directory: ${{ matrix.dir }}
      - run: tofu validate
        working-directory: ${{ matrix.dir }}

  test:
    runs-on: ubuntu-latest
    needs: validate
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - run: tofu test
        working-directory: modules/vpc
```

For full apply on merge to main:

```yaml
  apply:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    needs: [lint, validate, test]
    environment: production   # gates on environment approval
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::...
          aws-region: us-east-1
      - run: tofu init
        working-directory: environments/aws/prod
      - run: tofu apply -auto-approve
        working-directory: environments/aws/prod
```

Use OIDC for cloud credentials (`configure-aws-credentials` with a `role-to-assume`) — never long-lived access keys in CI secrets.

## Don't / Do

| Don't | Do |
|---|---|
| Skip `tofu fmt -check` because "we'll format later" | Add it to CI on day one |
| Run `tofu validate` only — call it done | Add `tflint` and a security scanner; each catches different bugs |
| Disable failing lints repo-wide | Fix the code; inline `# tflint-ignore` with a reason if you must |
| `apt install terraform` / `brew install opentofu` for projects | Pin via `tenv`/`tfenv`; commit `.opentofu-version` |
| Both `trivy` and `checkov` in CI | Pick one |
| Suppress security findings without a reason or expiry | Inline comment with `# reason: …` and a follow-up issue |
| Hand-written `README.md` that drifts from `variables.tf` | `terraform-docs` injected into `README.md` via pre-commit |
| Long-lived AWS access keys in CI secrets | OIDC with `aws-actions/configure-aws-credentials` |
| Terragrunt for 2 environments | Just copy `backend.tf` and `provider.tf` |
| Pre-commit hook with no CI equivalent | Mirror pre-commit in CI so the gate works for everyone |
