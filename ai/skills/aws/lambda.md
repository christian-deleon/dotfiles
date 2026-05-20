# Lambda

Lambda is a request-scoped runtime: AWS hands you a freshly-warm container, executes your handler with an event payload, and bills per millisecond. The mental model: **a function is a deployment unit, an execution role, a runtime, an event source, a log group, and a set of resource limits**. The right defaults in 2026 are **`arm64` architecture, latest supported runtime, log retention set explicitly, secrets fetched at cold-start (not via env vars), VPC only when required, and the timeout/memory matched to the actual workload**.

The most common AI failure mode: 15-minute timeout for a 200ms function, plain-text secrets in environment variables, `x86_64` on a runtime that supports `arm64`, `nodejs16.x` or `python3.9` in 2026, log retention left at "never expire", and dropping the function into a VPC "for safety" when nothing it touches needs VPC.

## Defaults

| Concern | Default |
|---|---|
| Architecture | **`arm64`** (Graviton) — ~20% cheaper than x86 |
| Runtime | **Latest supported** for the language — `python3.13`, `nodejs22.x`, `provided.al2023` for compiled |
| Package | **Container image** for >50MB or non-trivial deps; **zip** for small handlers |
| Memory | Right-size with Lambda Power Tuning — never just leave the default |
| Timeout | **The actual budget**, never 15 minutes by default |
| Log retention | **Explicit** — 30d nonprod, 365d prod |
| Tracing | **AWS X-Ray active** for anything user-facing |
| VPC | **No VPC** unless the function calls private resources |
| Concurrency | Default unreserved; reserve only when measured |
| Secrets | **Parameters / Secrets extension** or fetch on cold-start; never plain env vars |

## Runtime selection

| Language | Default runtime (2026) |
|---|---|
| Python | `python3.13` |
| Node.js | `nodejs22.x` |
| Go | `provided.al2023` + `bootstrap` binary (no managed runtime since 2024) |
| Rust | `provided.al2023` + `bootstrap` binary (Cargo Lambda) |
| Java | `java21` |
| .NET | `dotnet8` |

AWS deprecates runtimes about 24 months after the language EOLs. Stay on **N or N-1**, never **N-2** — the deprecation window is hard, and once your runtime is "deprecated phase 2" you can't update the function until you migrate.

Run `aws lambda list-functions --query 'Functions[*].[FunctionName,Runtime]'` to audit; flag anything on a deprecated runtime.

## Architecture — pick ARM by default

```hcl
resource "aws_lambda_function" "this" {
  architectures = ["arm64"]
  # ...
}
```

ARM64 is the default. Blockers:

- A native dep with no ARM build — rare for new code; check `pip install` / `npm install --arch=arm64` works.
- A vendor layer that's x86-only (some monitoring agents).

When ARM is blocked, fall back to `x86_64`. Never mix architectures across functions in the same app — it makes debugging unreliable.

## Packaging — zip vs container

| Choose zip when | Choose container when |
|---|---|
| Handler + small deps, <50 MB packaged | Heavy deps (ML, native libraries, browsers) |
| Pure Python / Node / etc., no compiled bindings | Compiled language with non-trivial build (Rust, Go with custom CGo) |
| Cold-start sensitivity is high | You want consistent local-dev environment |
| Deploying ~weekly | Image-tag-based rollouts via ECR |

Container limits: **10 GB image size, 500 MB ephemeral disk default** (raise to 10 GB if needed). Zip limits: **50 MB zipped / 250 MB unzipped including layers**, **10 MB inline**.

If you're going container, use the AWS-provided base images (`public.ecr.aws/lambda/python:3.13-arm64`, etc.) — they include the runtime interface emulator for local testing.

### Layers — use sparingly

Layers reduce package size and let you share code, but they:

- Add cold-start overhead.
- Couple functions to a numbered version that you have to bump everywhere.
- Hide dependencies from the build.

For most new code, bundling deps into the package or container is simpler. Layers are useful for **AWS-published extensions** (Parameters & Secrets, Lambda Insights, etc.) — those are the right kind of layer.

## Memory and timeout

The Lambda CPU and network allocation scale with memory. **Don't pick memory at random** — use [Lambda Power Tuning](https://github.com/alexcasalboni/aws-lambda-power-tuning) to find the optimum for your workload (it's a Step Functions state machine you deploy once and run per function). The cheapest setting is often *higher* than you'd guess, because the runtime gets faster.

Timeout rules:

- **Synchronous (API Gateway, ALB)**: ≤29s (API Gateway hard cap is 29s; if you're at 25s+, you have an architecture problem).
- **Async invocations (SNS, S3, etc.)**: long enough to complete; AWS retries automatically on failure.
- **SQS batch processing**: must be ≤ visibility timeout / 6 (AWS recommendation).
- **15-minute max** is a backstop, not a default.

Always set a `timeout` explicitly — the default of 3s catches new authors off-guard.

## Environment variables and secrets

Plain `environment_variables` are **fine for config**, **not for secrets**:

```hcl
environment {
  variables = {
    LOG_LEVEL    = "INFO"
    DB_HOST      = aws_db_instance.this.address       # ok — not secret
    DB_PORT      = aws_db_instance.this.port
    SECRETS_NAME = aws_secretsmanager_secret.this.name  # ARN/name only, not the value
  }
}
```

For secrets, two patterns — pick one per project, don't mix:

### Pattern A: Parameters & Secrets Lambda Extension

AWS-published layer that runs as a sidecar and exposes a localhost HTTP endpoint to fetch SSM Parameter Store / Secrets Manager values with caching:

```hcl
layers = [
  "arn:aws:lambda:us-east-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension-Arm64:11"
]
```

Then the handler calls `http://localhost:2773/...`. First call is slow; subsequent cached. **The right default** for high-frequency secret access.

### Pattern B: Fetch on cold-start

For low-frequency invocations or simpler code, fetch once at module load:

```python
import os
import boto3

_secret_cache = None

def _get_secret():
    global _secret_cache
    if _secret_cache is None:
        client = boto3.client("secretsmanager")
        _secret_cache = client.get_secret_value(SecretId=os.environ["SECRETS_NAME"])["SecretString"]
    return _secret_cache


def handler(event, context):
    secret = _get_secret()
    # ...
```

Module-level fetch runs once per container, persists across warm invocations.

### Don't:

- Pass the secret value as an `environment_variables` entry. It's visible in the console, in `GetFunction` API responses, and in CloudFormation/Tofu state. Treat env-var values as observable.
- Hardcode secrets in the code.

## Log retention — set it explicitly

```hcl
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = 30   # nonprod; 365 in prod
  kms_key_id        = aws_kms_key.checkout.arn
}
```

The log group is auto-created by Lambda on first invocation **with no retention** — managing it explicitly in HCL gives you retention from day one and removes a manual step.

For high-cardinality logs, consider **Lambda → Kinesis Firehose → S3** instead of CloudWatch — CloudWatch logs are expensive at scale.

## Triggers / event sources

| Trigger | Notes |
|---|---|
| **API Gateway / ALB** | Synchronous; 29s hard cap on API GW |
| **EventBridge** | Cron + event patterns; preferred over scheduled Lambda alone |
| **SQS** | Set `batch_size` and `maximum_batching_window_in_seconds`; configure DLQ |
| **S3** | Direct or via EventBridge — EventBridge gives filtering + multi-target |
| **DynamoDB Streams / Kinesis** | Shard-level concurrency; tune `parallelization_factor` |
| **SNS** | Fan-out; async only |

For SQS triggers, **always configure a dead-letter queue** with `redrive_policy`. Without it, failing messages retry forever and your bill grows.

```hcl
resource "aws_sqs_queue" "main" {
  name = "prod-checkout-events"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "dlq" {
  name                      = "prod-checkout-events-dlq"
  message_retention_seconds = 1209600   # 14 days
}
```

Set up a CloudWatch alarm on `ApproximateNumberOfMessagesVisible > 0` on the DLQ — DLQ messages mean broken processing.

## VPC — only when required

Putting a Lambda in a VPC means:

- Cold starts include ENI attachment (now ~100ms — was once 10+s, much improved).
- Egress to the internet requires NAT (cost).
- AWS API calls (DynamoDB, S3, etc.) need VPC endpoints or NAT.
- Concurrency limited by available IPs in the subnets.

**Don't VPC-attach by default.** Attach when the function needs to reach private resources:

- RDS / ElastiCache in private subnets.
- On-prem via VPN/Direct Connect.
- VPC-only API Gateway.

If you do VPC-attach:

```hcl
vpc_config {
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.lambda.id]
}
```

Use the private subnets, span all AZs, and create VPC endpoints for any AWS service the function calls (see [networking.md](networking.md)) to avoid NAT charges.

## Concurrency

| Setting | When |
|---|---|
| **Unreserved (default)** | Most workloads — Lambda autoscales |
| **Reserved concurrency** | Cap a function to protect downstream (DB) or guarantee budget |
| **Provisioned concurrency** | Latency-sensitive — keeps N containers warm |

Provisioned concurrency costs money continuously; only use it when measured cold-start latency is breaking SLOs. Combined with **Application Auto Scaling**, you can ramp provisioned concurrency by time of day.

## Observability

- **Structured JSON logs.** Use `aws-lambda-powertools` (Python/Node/Java/.NET) or `slog` (Go). Stop using `print` / `console.log` with free-form strings.
- **AWS X-Ray** enabled — `tracing_config { mode = "Active" }`. CloudWatch ServiceLens stitches X-Ray + logs + metrics.
- **Lambda Insights** if you need detailed CPU/memory/disk metrics per invocation; adds a layer.
- **Embedded Metric Format (EMF)** for high-cardinality custom metrics without per-PutMetric calls.

## Function naming

Standard pattern:

```
<env>-<app>-<purpose>

prod-checkout-stripe-webhook
prod-checkout-receipt-pdf
prod-platform-cost-reporter
```

The CloudWatch log group becomes `/aws/lambda/<function-name>` automatically — keep the function name readable.

## Don't / Do

| Don't | Do |
|---|---|
| `x86_64` for new work | `arm64` |
| `python3.9` / `nodejs16.x` (deprecated) | Latest supported runtime |
| 15-minute timeout default | Set to the actual workload budget |
| Secrets in `environment_variables` | Parameters & Secrets extension or fetch-once-on-cold-start |
| Skip log retention (defaults to "never expire") | Manage the log group explicitly with `retention_in_days` |
| Default `batch_size = 1` for SQS | Tune for throughput; configure DLQ |
| VPC-attach "for safety" | VPC-attach only when reaching private resources |
| Layer everything | Bundle deps; layers for AWS extensions / shared infra only |
| `print(...)` / `console.log(...)` | Structured logger (Powertools, `slog`) |
| Random memory size | Lambda Power Tuning |
| Tag-untagged Lambdas | Standard `<ns>:*` tags via `default_tags` |
| No DLQ on SQS-triggered function | Always a DLQ + alarm |
