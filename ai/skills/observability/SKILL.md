---
name: observability
description: Design and implement application instrumentation — logs, metrics, traces, levels, hot/critical paths. Use when adding logging, OpenTelemetry, RED metrics, spans, or reviewing AI-generated telemetry that is noisy, missing, or wrong. Defers k8s/LGTM platform wiring to the kubernetes skill.
compatibility: opencode
---

# Observability (Application Instrumentation)

Observability is the ability to explain **any** production behavior — including unknown-unknowns — from telemetry the system already emits, without shipping new code. Instrumentation is the design of that telemetry: **what** to emit, **where**, at what **cost**, and how signals **correlate**. Metrics, logs, and traces are not the goal; they are data types. The unit of analysis is the **request (or job) path** with enough high-cardinality context to slice by user, tenant, build, route, error class, and feature flag.

The most common AI failure mode is **decorative telemetry**: `INFO` logs that restate the code (`"Processing request"`), wrong levels (`ERROR` for expected 4xx / client mistakes), high-cardinality metric labels (`user_id`), spans around every function, zero instrumentation on the money/auth/mutation path, and no `trace_id` binding logs to traces. Noise without diagnostic power. This skill replaces that reflex with a deliberate placement algorithm.

**Platform stack** (Alloy, Loki, Tempo, Mimir, Grafana, ServiceMonitors) lives in the [`kubernetes` skill → observability.md](../kubernetes/observability.md). This skill owns **application-side design** that is language- and backend-agnostic. Prefer **OpenTelemetry** APIs + semantic conventions when the project has no stronger existing standard.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Choose log levels, structure, messages, what *not* to log | [logs.md](logs.md) |
| Design spans, attributes, propagation, sampling, wide events | [traces.md](traces.md) |
| RED/USE/golden signals, cardinality, histograms, exemplars | [metrics.md](metrics.md) |
| Place instrumentation on critical vs hot paths, boundaries, batch/async | [placement.md](placement.md) |
| Review or retrofit instrumentation on a feature/service | [checklist.md](checklist.md) |

For a one-off "add a log here" the cheat sheets below are usually enough. Reach for the reference files when instrumenting a service, a critical path, or reviewing AI-generated telemetry.

## First: discover before inventing

Before adding any signal:

1. **What does the project already use?** Grep for `otel`, `opentelemetry`, `prometheus`, `slog`, `zap`, `logrus`, `structlog`, `tracing`, `meter`, `metrics.`, `logger.`, existing middleware.
2. **Match existing patterns** — same logger type, same meter names, same span attribute style, same middleware layer. Do not introduce a second stack.
3. **Identify the unit of work** — HTTP/gRPC request, queue message, cron run, stream record, CLI command. Instrumentation hangs off that unit.
4. **Identify critical vs hot** (see below). They need opposite treatments.

If the project has no observability at all and the user only asked for a small feature, add **minimal boundary instrumentation** (request metrics + root span or structured request log) rather than boiling the ocean — then note the gap.

## Signal selection — which tool answers which question

| You need to… | Prefer | Not |
|---|---|---|
| Follow **one request** across services | **Trace** (spans) | A trail of uncorrelated log lines |
| **Alert** on rate / error % / latency SLO | **Metric** (counter + histogram) | Parsing log volume |
| Answer **"why this user / tenant / build?"** | **Wide attributes** on the root span (or one canonical log line) | Metric labels for every dimension |
| Record a **rare decision** or payload-shaped forensic detail | **Structured log** (once) or span event | Per-iteration DEBUG spam |
| Find **CPU / memory** hotspots | **Continuous profile** (eBPF or SDK) | Guessing from logs |
| Resource bottleneck (CPU, disk, nic, pool) | **USE** metrics | Only RED |
| Service health at the interface | **RED** / four golden signals | Only host CPU |

**Default stack for a request-handling service:**

1. **Auto / middleware**: inbound RED metrics + root server span + context propagation.
2. **Outbound clients**: client spans + client RED (HTTP, gRPC, DB, queue, cache).
3. **Domain**: attributes on the active/root span for business context (tenant, plan, outcome).
4. **Failures**: span status + `error.type` + **one** ERROR log with the error and key fields (not a stack of "failed… failed… failed…").
5. **Logs**: structured JSON; always include `trace_id` / `span_id` when a context exists.

Logs are for humans and forensic detail. Metrics are for cheap aggregation and pages. Traces are for causality and latency decomposition. Prefer putting a dimension on a **span attribute** (high cardinality OK in modern trace backends) rather than a **metric label** (cardinality kills metrics backends).

## Critical path vs hot path

These are not the same thing. AI constantly confuses them.

| | **Critical path** | **Hot path** |
|---|---|---|
| Definition | Wrong or silent failure costs users money, data, security, or trust | Executes at very high frequency (tight loops, per-item, per-packet) |
| Examples | Checkout, authn/z, payment, permission checks, data deletion, schema migrations, webhook delivery with side effects | Serialization loops, per-row map, cache get in a tight loop, metric scrape handlers, health checks |
| Instrumentation | **Rich and mandatory** — spans, outcome attributes, ERROR on failure, business metrics | **Cheap and sparse** — counters/histograms; no per-iteration logs; child spans only if work is I/O or meaningfully slow |
| Cost tolerance | Pay for visibility | Optimize for zero overhead when healthy |

A path can be both (e.g. per-event billing at 50k RPS). Then: **metrics always**, **sampled traces**, **errors always recorded**, **no INFO per event**.

## Placement algorithm (the core loop)

When instrumenting a function, handler, or service, walk this in order:

```
1. BOUNDARY?
   Inbound request / message / job start  → root span + RED metrics
   Outbound dependency call               → child CLIENT/INTERNAL span + client RED
   Process lifecycle (start/stop)         → INFO once + uptime/build metrics

2. CRITICAL?
   Money, auth, mutation, irreversible    → attributes for outcome + actor + target
                                            ERROR log on failure (once, with err)
                                            span status Error + error.type

3. HOT?
   Tight loop / per-item at high QPS      → NO log per iteration
                                            NO span per iteration unless I/O
                                            Counter/histogram only (or batch attrs)

4. DECISION / BRANCH?
   Significant business branch            → span attribute (preferred) or DEBUG
                                            never INFO "taking branch A"

5. FAILURE?
   Operation cannot complete as intended  → see log-level rules
   Recovered / retried                    → WARN once at finality or metric + span event
   Expected client mistake (4xx)          → not ERROR on the server

6. STILL TEMPTED TO LOG?
   Would this line help an on-call engineer at 3am on a novel failure?
   If no → delete. If only with a debugger → DEBUG. If always valuable → INFO or span attr.
```

Full boundary tables and async/batch patterns: [placement.md](placement.md).

## Log levels — non-negotiable definitions

Levels encode **severity and audience**, not developer mood.

| Level | When | Production default |
|---|---|---|
| **TRACE** | Step-through inside a function ("entering loop i=3") | Off |
| **DEBUG** | Diagnostic detail useful while investigating; safe to disable | Off (or sampled) |
| **INFO** | Significant lifecycle / state change you want in normal ops history | On |
| **WARN** | Unexpected but **handled**; degraded mode; retries exhausted soon; config smell | On |
| **ERROR** | **This operation failed**; needs human or automated attention; not fatal to process | On |
| **FATAL** / **CRITICAL** | Process cannot continue safely; about to exit | On (rare) |

Hard rules:

- **Server 4xx from bad client input → not ERROR.** Attribute `http.response.status_code=400`; log at DEBUG/INFO if needed. ERROR is for *your* failure to serve a valid request (5xx, dependency down, bug).
- **Never log-and-return the same error at every layer.** Log at the boundary that owns the response (or where the error becomes non-propagated); elsewhere `return err` with wrap context.
- **One ERROR per failure.** Not "connecting…", "retry 1…", "retry 2…", "giving up" all at ERROR.
- **Messages are events, not sentences about code.** Prefer `checkout.payment_failed` style or a short verb phrase + structured fields: `msg="payment capture failed" order_id=… err=…`.
- **No secrets, tokens, passwords, raw auth headers, full card numbers, session cookies.** Redact at source; collectors are not a safety net you rely on alone.

Deep guidance: [logs.md](logs.md).

## Metrics — cardinality and shape

| Instrument | Use for |
|---|---|
| **Counter** | Requests, errors, bytes, jobs completed (monotonically increasing) |
| **Histogram** | Latency, payload size (need percentiles) |
| **UpDownCounter / gauge** | In-flight requests, queue depth, pool size |
| **Observable gauge** | Build info, config flags, cache size sampled on scrape |

**Never** put unbounded or high-cardinality values on metric labels: `user_id`, `email`, `request_id`, `order_id`, `session_id`, full URL path with IDs, exception messages. Use **exemplars** (trace_id on a metric sample) or span/log fields instead.

**Always** prefer **route templates** (`/users/{id}`) over raw paths (`/users/12345`) on metrics and span names.

RED per service interface (and per critical dependency):

- `*.request` / `*.requests` — count
- `*.duration` — histogram (seconds)
- errors via `error.type` or status class attribute on the same instruments

Deep guidance: [metrics.md](metrics.md).

## Traces — minimal viable design

1. **One root span per unit of work** (inbound request / consumed message / job).
2. **Child spans at dependency boundaries** and slow/significant internal work — not every function.
3. **Span name**: low-cardinality, `{method} {route}` or `{operation}` — never include IDs.
4. **Attributes**: high-cardinality context belongs here (user, tenant, order_id, build, feature flags).
5. **Status**: unset on success; `Error` + `error.type` on failure. Do not mark server spans Error solely for 4xx.
6. **Propagate** W3C `traceparent` (and baggage only for non-sensitive routing dimensions).
7. **Sample** with purpose: prefer tail sampling (keep errors + slow + N% baseline) over blind 1% head sample alone when volume is high.
8. **Wide events**: pack request context onto the root span so one row answers "what happened?" — see [traces.md](traces.md).

## Correlation — non-optional glue

Without correlation, three signal types are three blind men:

- Every log line in a request context includes **`trace_id`** (and ideally `span_id`).
- Metrics use **exemplars** linking latency samples to traces where the stack supports it.
- Resource attributes (`service.name`, `service.version`, `deployment.environment`, k8s pod/node) are **identical** across signals (OTel Resource).
- Downstream services receive propagated context — instrument clients or use auto-instrumentation; do not invent a custom header when W3C Trace Context fits.

## AI anti-patterns (reject on sight)

| Anti-pattern | Fix |
|---|---|
| `log.Info("starting function X")` / `"done with X"` | Delete; use a span if the work matters |
| `log.Error(err)` at every stack frame | Wrap and return; log once at ownership boundary |
| `ERROR` for validation / NotFound / unauthorized (expected) | DEBUG/INFO + correct status code attributes |
| Metric label `user_id=…` | Span attribute or log field |
| Span per loop iteration over 10k items | One span for the batch; counter for items; optional attributes summary |
| Logging full request/response bodies by default | Sample, redact, size-cap; prefer content-type + byte size |
| Only happy-path logs | Instrument failures and dependency errors first |
| New logging library when one exists | Extend the project's logger |
| `fmt.Println` / `print(` / `console.log` in services | Structured logger or OTel |
| Trace without metrics (or metrics without any request identity) | RED at the boundary + root span together |
| Health/ready probes as ERROR when failing under load noise | Separate probe metrics; don't page on single probe blip without `for:` |
| "Added logging" as the whole observability plan for a critical feature | Checklist in [checklist.md](checklist.md) |

## Universal rules

1. **Discover existing telemetry conventions in the repo before adding anything.** Consistency beats perfection.
2. **Instrument boundaries and critical paths first** — inbound, outbound, auth, money, mutation. Interior noise last (usually never).
3. **Structured logs only** in services (JSON or key=value). Plain text is a last resort for CLIs writing to humans.
4. **OpenTelemetry semantic conventions** for attribute and metric names when inventing new ones would collide; company/app prefix for proprietary business fields (`acme.order.tier`).
5. **Low-cardinality names, high-cardinality attributes.** Span/metric *names* are identities; *attributes/fields* hold the variance.
6. **Hot path: no per-item logs, no per-item spans** unless the item is itself I/O.
7. **Critical path: always record outcome** (success/fail/reason) in a queryable form.
8. **Errors propagate as values** (Go/Rust) or exceptions (Java/Python) with context; telemetry records them — it does not replace error handling.
9. **Never emit secrets.** Assume every backend is readable by a broad eng audience.
10. **Sampling and level gates are production features**, not afterthoughts. High-volume services plan them on day one.
11. **Prefer span attributes over INFO logs** for request-scoped context that should be queryable with the trace.
12. **Alert on symptoms (SLO burn, golden signals), not causes alone** — but instrument causes so the page is diagnosable.

## Language defaults (when the project has no stronger standard)

| Language | Logs | Traces / metrics |
|---|---|---|
| Go | `log/slog` + `otelslog` bridge | `go.opentelemetry.io/otel`, `otelhttp`, `otelpgx` |
| Python | `structlog` or stdlib + JSON; bridge to OTel | `opentelemetry-*` instrumentation packages |
| Rust | `tracing` + `tracing-opentelemetry` | OTel OTLP exporter; `metrics` crate or OTel metrics |
| Java | existing framework logger → OTel appender | Java agent zero-code + manual spans for business |
| Node/TS | `pino` (structured) | `@opentelemetry/sdk-node` + auto instrumentations |
| .NET | `ILogger` structured | OpenTelemetry .NET |

Defer language idioms to the language skill; this table is only the observability default.

## What this skill defers

| Concern | Where |
|---|---|
| Alloy / Loki / Tempo / Mimir / Grafana wiring, ServiceMonitors, k8s events | [`kubernetes` → observability.md](../kubernetes/observability.md) |
| Language idioms (slog handlers, error wrap) | `go`, `python`, `rust`, … skills |
| Alertmanager routing, on-call policy | Ops runbooks; SRE practices — only light notes here |
| Product analytics (funnels, marketing events) | Not ops telemetry; keep pipelines separate |

## Don't / Do

| Don't | Do |
|---|---|
| Log "entering/leaving" every function | Span the unit of work; attributes for context |
| `ERROR` for expected client errors | Correct status attribute; ERROR only for server-side failure |
| Metric labels with user/request IDs | Span attributes + exemplars |
| Raw URL paths as metric labels | Route templates (`/orders/{id}`) |
| Three ERROR logs for one failure | One ERROR at ownership boundary; wrap elsewhere |
| INFO in a 100k-iteration loop | Counter + optional DEBUG sampled |
| New observability stack beside the existing one | Extend what's there |
| Traces without log correlation | Inject `trace_id` into every structured log in context |
| Head-sample 1% and hope you catch errors | Tail-keep errors + slow + baseline % |
| Instrument only the happy path | Failures and dependency calls first |
| Log secrets "for debugging" | Redact; use secure debug channels if ever needed |
| Span name `processOrder_user_12345` | Span name `process_order`; attribute `user.id` |

## Adding to this skill

When a new convention lands, put depth in the matching topic file and a one-line pointer in the decision tree. Keep `SKILL.md` under ~500 lines — the decision tree is the contract.
