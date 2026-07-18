# Metrics

Metrics are **cheap, aggregatable** measurements over time. They power dashboards, SLOs, and pages. They deliberately discard per-request identity at write time (except via **exemplars**), which makes them hostile to "why this one user?" questions — use traces/logs for that. Good metrics are few, stable, and low-cardinality.

## Golden signal methods

Use the method that matches the thing under study:

### Four golden signals (Google SRE) — user-facing systems

| Signal | Meaning | Typical instrument |
|---|---|---|
| **Latency** | Time to serve (separate success vs error latency) | Histogram |
| **Traffic** | Demand (RPS, sessions, consumer lag input rate) | Counter / gauge |
| **Errors** | Failed requests (explicit, implicit, policy/SLO breach) | Counter (ratio) |
| **Saturation** | How full (pool, queue, CPU, memory, disk) | Gauge / histogram |

### RED (Tom Wilkie) — request-driven services

For each service **interface**:

- **Rate** — requests per second  
- **Errors** — failed requests per second (or ratio)  
- **Duration** — distribution of latency  

Apply RED to: inbound API, and each critical dependency client (DB, billing API, Kafka produce).

### USE (Brendan Gregg) — resources

For each resource: **Utilization**, **Saturation**, **Errors**.

Resources: CPU, memory, disk I/O, network, thread pools, connection pools, file descriptors.

USE finds bottlenecks; RED finds bad service behavior. You want both. App code usually emits RED + pool saturation; the platform emits host USE (node-exporter, cAdvisor, eBPF).

## Instrument types

| Type | Behavior | Examples |
|---|---|---|
| **Counter** | Monotonic increase | `http.server.request.duration` count side, `errors_total`, bytes sent |
| **UpDownCounter** | Up and down | queue depth, in-flight requests |
| **Histogram** | Distribution → percentiles | latency, payload size |
| **Gauge** (observable) | Point-in-time sample on collect | build info (1), temperature, cache entries |

OpenTelemetry naming (preferred for new work):

- Duration histograms: `{area}.{client\|server}.{name}.duration` (e.g. `http.server.request.duration`) in **seconds**.
- Do not append `_total` in OTel API names the way raw Prometheus client code often does — the exporter bridges conventions.
- If the project is pure Prometheus client without OTel, follow existing Prometheus naming (`namespace_subsystem_name_unit`) and stay consistent.

## Cardinality — the #1 metrics footgun

A time series is roughly unique(**metric name × label set**). Explosion = cost, slow queries, missed alerts.

### Never as metric labels

- `user_id`, `email`, `session_id`, `request_id`, `trace_id`
- `order_id`, full `url`, raw path with ids (`/users/123`)
- Exception messages, stack hashes at infinite variety
- Free-text `reason` with unbounded values

### Safe / usual labels

- `service.name` / `job` / `namespace` (often resource/target labels)
- `http.request.method`
- `http.route` (**template**, not raw path)
- `http.response.status_code` or status **class** (`2xx`, `5xx`) if budget is tight
- `error.type` with a **bounded** enum
- `deployment.environment`
- Dependency: `server.address` only if the set of peers is small/stable

### If you need high cardinality

Put it on a **span attribute** or **log field**. Link metrics → traces with **exemplars** (attach `trace_id` to a histogram sample) so "p99 spike" jumps to an example request.

## Histograms and latency

- Prefer **histograms** over summary when you need server-side aggregation across instances (Prometheus/OTel).
- Choose buckets for **your SLO** (include boundaries at the SLO target, e.g. 0.1, 0.25, 0.5, 1, 2.5, 5, 10s).
- **Never alert on mean latency alone.** Use p95/p99 or SLO burn (fraction of requests over threshold).
- Track **success and error latency separately** when errors are fast-fail — mixed averages lie.

## RED metric set (minimal service)

Per inbound interface:

```text
http.server.request.duration{http.request.method, http.route, http.response.status_code}
  — histogram (seconds); count = rate, sum/count = mean, buckets = percentiles

// Or split:
requests_total{method, route, status_class}
request_duration_seconds{method, route}  // histogram
```

Per dependency:

```text
http.client.request.duration{server.address, method, status_code}
db.client.operation.duration{db.system.name, db.operation.name}
```

Saturation:

```text
db.client.connection.count{state=used|idle}
queue.depth
runtime.goroutines / jvm.threads / process.cpu.utilization
```

## Business metrics

Product counters are fine when **bounded**:

- `orders_completed_total{plan_tier, payment_provider}` — OK if tiers/providers are few
- `orders_completed_total{user_id}` — **not OK**

Prefer outcome enums: `result=success|declined|fraud_hold`.

Do not confuse **product analytics** (funnels, marketing) with **ops metrics** — separate pipelines/retention when possible.

## SLIs, SLOs, and alerting (instrumentation implications)

Instrumentation must support the SLI:

| SLI shape | Need from code |
|---|---|
| Availability = non-5xx / total | Status codes on request metrics |
| Latency = % faster than 300ms | Histogram buckets including 0.3s |
| Correctness | Explicit success criteria, not just HTTP 200 |

Alerting rules belong in the platform, but bad instrumentation makes good alerts impossible:

- No `for:` duration → flappy pages (platform concern).
- No status label → cannot compute error ratio.
- High-cardinality routes → alert queries timeout.

Prefer **multi-window multi-burn-rate** SLO alerts over "error count > N".

## Exemplars

When the stack supports them (Prometheus + OTel, Grafana):

- Latency histogram samples carry `trace_id` of an example request.
- Lets you jump from "p99 blew up at 14:02" → actual trace.

Enable exemplars on server middleware metrics; do not invent a parallel "log every slow request" at INFO if exemplars + tail sampling exist.

## What not to metric

| Avoid | Prefer |
|---|---|
| One metric per function call count for thousands of internals | Trace spans + few RED metrics |
| Updating gauges on every request in a hot path without care | Counters/histograms designed for concurrent updates |
| Scrape-time heavy computation | Pre-aggregate or sample |
| Duplicate metrics under three names for the same thing | One name, stable labels |

## Health checks

- `health` / `ready` endpoints: **exclude from RED SLOs** or label `http.route=/healthz` and filter out of burn rates.
- Do not create a high-cardinality series per probe source IP.

## Anti-patterns

| Bad | Fix |
|---|---|
| Label = customer name | Opaque tenant id on span; tier on metric if ≤ tens of values |
| Timer as summary only in multi-replica deploy | Histogram |
| Counting only errors, never totals | Need both for ratio |
| `duration_ms` gauge set to last latency | Histogram |
| Different label names per service for the same idea | Semconv / org style guide |
| Metrics for one-off debug ("is this code path hit?") | Temporary DEBUG log or span event; remove later |

## Don't / Do

| Don't | Do |
|---|---|
| `user_id` metric label | Span/log field + exemplar |
| Raw path label | Route template |
| Mean latency SLO | Percentile or threshold fraction |
| 50 custom metrics on day one of a CRUD service | RED inbound + RED on primary DB + pool saturation |
| Alert on `errors > 0` | Error ratio / SLO burn with `for:` |
| Inventory every internal function | Boundaries and dependencies |
