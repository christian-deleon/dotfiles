# Placement — Where Instrumentation Goes

Instrumentation is a **design decision at boundaries**, not a seasoning you sprinkle after every line of business logic. This file answers *where* for request/response services, workers, batch jobs, and hot loops.

## Map the system first

Before editing code, sketch (even mentally):

```
[Client] → [Edge/API] → [Service A] → [DB]
                      ↘ [Service B] → [Queue] → [Worker] → [S3]
```

For each arrow: **who calls whom**, sync vs async, and what "failure" means. Telemetry should make that diagram reconstructable from a single trace id.

## Tiered placement

### Tier 0 — Process (once)

| Site | Signal |
|---|---|
| Startup | INFO: version, env, critical config (redacted); metric `process_start` / build info gauge |
| Shutdown | INFO; flush telemetry exporters (OTel shutdown) |
| Fatal config missing | ERROR/FATAL and exit |

### Tier 1 — Unit-of-work boundary (always for services)

| Site | Metrics | Traces | Logs |
|---|---|---|---|
| HTTP/gRPC **server** middleware | RED histogram + counts | Root SERVER span; extract context | Canonical line **or** errors only |
| Queue **consumer** handler entry | Consume rate, lag (platform), handler RED | CONSUMER span; extract from message | ERROR on handler failure / poison |
| Cron / scheduled job | Run count, duration, success/fail | Root INTERNAL/CONSUMER span per run | Start/end INFO; ERROR on fail |
| CLI one-shot | Exit code metric optional | Optional root span | Human-oriented stderr + structured if automated |

**Implement once in middleware/framework hooks**, not copy-pasted into every handler.

### Tier 2 — Dependency boundary (always for critical deps)

| Site | Metrics | Traces | Logs |
|---|---|---|---|
| HTTP client | Client RED | CLIENT span + propagation inject | ERROR only if not propagated to caller who logs |
| gRPC client | Same | Same | Same |
| DB / ORM | Operation duration, pool USE | CLIENT/INTERNAL span per query **or** batch | Slow query WARN if over threshold (sampled) |
| Cache | Hit/miss counters; latency histogram if multi-ms | Span only if remote/significant | No per-hit logs |
| Queue producer | Publish rate/errors | PRODUCER span + inject context | ERROR on publish fail |
| Third-party SDK (payments, email) | RED + `error.type` | CLIENT span | ERROR with provider code; never log full PAN/PII |

Prefer **library instrumentation** (OTel plugins) over hand-wrapping every call. Hand-wrap when the library is custom or business-critical and auto is blind.

### Tier 3 — Domain critical path (mandatory when present)

These are **critical** regardless of QPS:

| Domain event | Minimum instrumentation |
|---|---|
| Authentication success/failure | Metric by result; span attrs `enduser.id` / auth method; lockout/anomaly → WARN/metric |
| Authorization deny | Metric; attribute `authz.decision=deny` + reason code (bounded); DEBUG detail |
| Payment / money movement | Span + attrs (amount **bucket** or currency, provider, result); ERROR on unexpected fail; provider decline may be OK outcome attr not ERROR |
| Inventory reserve / commit | Span; outcome attr; compensation steps INFO |
| Data deletion / GDPR | Audit log + span; success/fail |
| Password/token/credential change | Audit log |
| Idempotency conflict | Metric; attribute; DEBUG/INFO not ERROR if expected |
| Schema migration | INFO start/end; ERROR fail; block deploy on fail |

On these paths: **record outcome even when successful** (attribute or metric). Silence on the critical path is a bug.

### Tier 4 — Interior logic (selective)

| Situation | Placement |
|---|---|
| Multi-step algorithm with independent failure modes | Child INTERNAL spans for steps that are slow or branch externally |
| Feature flag branch that changes behavior | Span attribute `feature.x=true` |
| Validation | Usually no span; 4xx status on root; no ERROR log |
| Pure compute <1ms | Nothing |
| Loop over N items | See hot path section |

## Hot paths — rules of engagement

A path is **hot** if it runs at high frequency relative to process resources: per-request inner loops, per-element batch processing, per-tick game/simulation loops, message handlers at tens of thousands/sec.

### Hard rules

1. **No INFO/ERROR logs per iteration** of a tight loop. Aggregate: `processed=10_000 errors=3` at the end, or metrics only.
2. **No child span per iteration** unless each iteration performs I/O or is itself a unit of work (e.g. each email send).
3. Prefer **one span** around the batch: attributes `items.count`, `items.failed`, `items.bytes`.
4. Use **counters/histograms** for per-item outcomes when you need rates.
5. **Level-gate** debug: `if logger.DebugEnabled()` / structured APIs that skip work when disabled.
6. Health/metrics **scrape handlers** must not log at INFO per scrape.
7. Avoid allocating huge attribute maps on spans in the hottest code — set attributes sparingly.

### Pattern: batch processor

```text
ctx, span = Start(ctx, "process_batch")
defer End()
var ok, fail int
for item in batch:
    err = process(ctx, item)  // process may create spans only for external I/O
    if err: fail++; record metric error; continue  // or break by policy
    else: ok++
span.SetAttributes(items.ok=ok, items.fail=fail)
if fail > 0 && policy hard:
    span.SetStatus(Error)
    log.Error("batch completed with failures", ok, fail)
```

### Pattern: hot cache lookup

```text
// metrics: cache_lookup_total{result=hit|miss}
// NO log on hit
// optional: DEBUG on miss only if investigating
// span: usually none; parent request span already exists
```

## Critical + hot together

Example: billing event at 20k events/sec.

| Signal | Choice |
|---|---|
| Metrics | `billing_events_total{result}` always |
| Traces | Tail sample: all `result=error`, 1% of OK; root span per event **or** per micro-batch |
| Logs | Only final failures / poison messages |
| Attributes | `tenant.id` on span (not metric label) |

## Async and messaging

```
Producer                     Broker                   Consumer
── PRODUCER span ──inject──► headers ──extract──► CONSUMER span
     (parent)                                           │
                                                        ├─ work
                                                        └─ CLIENT spans
```

- **Do not** continue the HTTP SERVER span as the only context after returning 202 — end the server span; consumer starts its own CONSUMER root (optionally **linked** to producer).
- Record `messaging.message.id`, destination, partition/offset when useful (cardinality: offset not as metric label).
- Poison messages: ERROR log + metric + do not infinite-retry without visibility.

## Retries and circuit breakers

| Event | Signal |
|---|---|
| Retry attempt | Span event `retry` with `attempt=n` **or** CLIENT span per attempt (`http.request.resend_count`) |
| Retry succeeded | Metric `retries_total`; no ERROR |
| Retries exhausted | ERROR log once + span status Error |
| Circuit open | Metric + WARN when state flips (not every rejected call at WARN — use metric for rejects) |

## What "done" looks like for a new endpoint

For `POST /v1/orders`:

1. Middleware: root span name `POST /v1/orders`, RED metrics with route template.
2. Handler sets `app.order.id` when created; `app.order.result` on completion.
3. DB and payment clients: child spans (auto or manual).
4. Failure paths: span status + single ERROR with order id when 5xx.
5. No "entered handler" / "exiting handler" logs.
6. Auth failures: 401/403 metrics via status code; no ERROR spam.

## Layering with frameworks

| Layer | Responsibility |
|---|---|
| Service mesh / ingress | Optional coarse RED; not a substitute for app traces |
| Framework middleware | Root span, metrics, context, canonical log |
| Application services | Domain attributes, critical path outcomes |
| Repositories / clients | Dependency spans (prefer auto) |
| Domain pure functions | Usually none |

Do not double-count: if middleware already increments request totals, handlers must not increment the same counter again.

## Anti-patterns by placement

| Bad placement | Why | Move to |
|---|---|---|
| Logging inside shared `utils/` used everywhere | Uncontrollable volume/level | Caller decides; utils return errors |
| Metrics in a library without a meter provider pattern | Global state mess | OTel API no-op default; app wires SDK |
| Spans in a tight JSON encoder | Overhead | None or profile |
| Only instrumenting the happy path in checkout | Silent money loss | Failure + decline outcomes first |
| Instrumenting tests with production exporters | Noise / cost | Noop or test SDK |

## Decision cheatsheet

```
New code path?
├── Is it a service boundary (in/out)?     → RED + span
├── Is it money/auth/mutation/security?    → outcome attrs + failure ERROR
├── Is it a tight loop / per-item hot?     → metrics only; batch span
├── Is it a rare branch / ops lifecycle?   → INFO log or span attr
└── Is it pure glue?                       → nothing
```
