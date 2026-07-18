# Instrumentation Checklist

Use this when **adding**, **reviewing**, or **retrofitting** observability on a feature or service. Work top to bottom. Skip rows that do not apply (e.g. no queue → skip messaging).

## 0. Recon (do first)

- [ ] Identified existing logger, metrics, and tracing libraries/patterns in the repo
- [ ] Identified unit of work (HTTP request, message, job, CLI)
- [ ] Listed external dependencies this code calls
- [ ] Marked **critical** paths (auth, money, mutation, irreversible)
- [ ] Marked **hot** paths (high-frequency loops, high RPS handlers)
- [ ] Confirmed env vars / SDK init already exist (OTel endpoint, service name) — or noted setup as separate work

## 1. Boundary coverage

- [ ] Inbound middleware/handler: **RED metrics** (rate, errors, duration histogram)
- [ ] Inbound: **root span** with low-cardinality name (method + route template)
- [ ] Inbound: context **extraction** (W3C `traceparent`) when applicable
- [ ] Outbound clients: **CLIENT spans** + propagation **injection**
- [ ] Outbound: client RED or dependency duration metrics for critical deps
- [ ] Route/path labels use **templates**, not raw ids
- [ ] Health/ready routes **excluded** from SLO error budgets (or filtered)

## 2. Critical path

- [ ] Success and failure **outcomes** recorded (attribute and/or metric enum)
- [ ] Failures set span **status Error** + `error.type` where appropriate
- [ ] **One** ERROR log at the ownership boundary (not every layer)
- [ ] Identifiers needed for support (`order.id`, `tenant.id`) on span or structured log — **not** as metric labels if unbounded
- [ ] Expected client failures (validation, 404, 401) are **not** ERROR logs
- [ ] Compensating transactions / rollbacks visible (INFO or span events)

## 3. Hot path

- [ ] No per-iteration INFO logs
- [ ] No per-iteration spans unless per-item I/O
- [ ] Batch summary attributes or metrics present where relevant
- [ ] Debug logging level-gated / not expensive when disabled
- [ ] High-volume success paths rely on metrics + sampled traces, not full log streams

## 4. Logs

- [ ] Structured (JSON or key-value fields), not free-form only
- [ ] `trace_id` (and ideally `span_id`) present when context exists
- [ ] Levels match definitions in [logs.md](logs.md)
- [ ] No secrets, tokens, passwords, raw auth headers, card data
- [ ] PII minimized / policy-compliant
- [ ] Stable `msg` strings for the same event type

## 5. Metrics

- [ ] Histograms for latency (not only gauges of "last value")
- [ ] Error **ratio** possible (errors + totals, or status on request metric)
- [ ] Label set **bounded** (reviewed for cardinality bombs)
- [ ] Saturation signals for constrained pools (DB pool, workers, queue depth) if this service owns them
- [ ] Exemplars enabled when stack supports them

## 6. Traces

- [ ] Span names low-cardinality
- [ ] Resource: `service.name`, `service.version`, environment set once
- [ ] Spans always ended (defer / finally / with)
- [ ] Async/messaging: produce/consume context + correct span kinds
- [ ] Sampling story exists for high RPS (tail keep errors/slow)
- [ ] Root/wide attributes for primary debug dimensions

## 7. Correlation & ops readiness

- [ ] Same service identity across logs, metrics, traces
- [ ] On-call can go **metric symptom → exemplar/trace → logs** without guessing hosts
- [ ] New pages (if any) have clear symptoms and a runbook stub — prefer SLO burn over raw counters
- [ ] Local/dev: can run with human-readable logs; staging/prod: JSON + OTLP (or project standard)

## 8. AI-generated telemetry review (fast pass)

Reject or fix if you see:

- [ ] `"Starting X"` / `"Finished X"` INFO pairs
- [ ] `ERROR` for NotFound / validation / unauthorized as a matter of course
- [ ] `user_id` (or similar) on Prometheus/OTel metric labels
- [ ] New logging framework imported beside the existing one
- [ ] `print` / `fmt.Println` / `console.log` in service code
- [ ] Spans or logs inside tight loops over large collections
- [ ] Empty `catch`/`if err` that only logs and swallows without metric/span
- [ ] Instrumentation only on the happy path of a critical feature
- [ ] Full request/response body logging enabled by default

## 9. Definition of done (feature-level)

The feature is **well-instrumented** when:

1. A failing request produces a **trace** that shows which dependency or step failed.
2. Dashboards/queries can show **rate, error ratio, and latency** for the new interface without log parsing.
3. An on-call engineer can filter to a **single tenant/order/user** (via trace/log fields) without a code change.
4. Healthy hot paths do **not** dominate log volume or metric cardinality.
5. No secret material appears in any signal.

## Suggested review comment templates

**Cardinality:**

> This label will create a series per `{user,order,request}`. Move it to a span attribute or log field; keep metric labels bounded.

**Level:**

> This is an expected client error (4xx). Prefer status-code metrics and DEBUG/INFO; reserve ERROR for server-side failures.

**Hot path:**

> This log/span sits in a per-item loop. Aggregate with a counter or a single parent span + summary attributes.

**Critical path:**

> This mutates `{money,auth,data}` but doesn't record outcome on the span/metric. Add a bounded `result` attribute and ensure failures set span status.

**Correlation:**

> Logs in this handler don't include trace context. Use the request-scoped logger / `*Context` methods so `trace_id` is injected.
