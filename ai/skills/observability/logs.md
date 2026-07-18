# Logs

Logs are discrete, timestamped events with a message and fields. In modern systems they should be **structured** (JSON or equivalent), **correlated** to traces, and **level-gated**. They are the wrong default for high-frequency aggregates (use metrics) and for multi-hop latency (use traces) — but they remain essential for forensic detail, security audit trails, and operator-readable narrative.

## Structure (always)

Every log line in a service should be machine-parseable:

```json
{
  "time": "2026-07-17T12:34:56.789Z",
  "level": "error",
  "msg": "payment capture failed",
  "service": "checkout",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "order.id": "ord_01H…",
  "error.type": "StripeCardError",
  "error.message": "card_declined",
  "http.route": "/v1/checkout",
  "http.response.status_code": 502
}
```

Required when available:

| Field | Purpose |
|---|---|
| `time` | RFC3339 / nanosecond timestamp |
| `level` | Severity |
| `msg` | Short, stable event description (not a paragraph) |
| `trace_id` / `span_id` | Correlation with active span |
| `service.name` (or equivalent) | Origin service |

Recommended request-scoped fields (on the log **or** better as span attributes that backends join): `http.route`, `http.request.method`, `user.id` / `tenant.id` (if non-PII policy allows), `error.type`.

**Message style:**

- Prefer **stable event phrases**: `"payment capture failed"`, `"cache warm complete"`, `"config reloaded"`.
- Avoid interpolated essays: `"Failed to process order " + id + " because " + err` as the only structure — put `order.id` and `err` in fields.
- Do not end messages with periods as prose; they are event names.
- Do not log at INFO what the span already records unless operators read logs without a trace UI.

## Level decision tree

```
Is the process about to crash / exit uncleanly?
  → FATAL / CRITICAL

Did THIS operation fail (cannot complete its contract)?
  → Is it an expected client/input problem (4xx, NotFound, validation)?
       → DEBUG or INFO (often: don't log; metrics + status code suffice)
  → Is it our bug, dependency failure, timeout, 5xx, data corruption risk?
       → ERROR (once, with err + key identifiers)

Did something unexpected happen but we recovered?
  → WARN (retry succeeded after N, fallback used, degraded mode, near limit)

Is this a normal, significant lifecycle event?
  (started, stopped, config loaded, migration applied, consumer group joined)
  → INFO

Is this only useful while actively debugging?
  → DEBUG

Is this step-through inside an algorithm?
  → TRACE (or delete)
```

### Level anti-patterns

| Bad | Why | Better |
|---|---|---|
| `ERROR: user not found` on public GET | Expected; pages on-call if ERROR→alert | 404 metric/status; DEBUG optional |
| `INFO: received request` + `INFO: sending response` every call | Volume + no value if you have access logs/spans | Root span + access log middleware once |
| `ERROR` then retry then success, still ERROR | False incident signal | DEBUG/WARN on retry; ERROR only on final failure |
| `DEBUG` left on in prod for everything | Cost, PII risk, I/O amplification | Default INFO; dynamic level or sampled DEBUG |
| Same failure logged in repository + service + handler | Triplicated noise | Log at the layer that **handles** (maps to response / DLQ / ignore) |

### "Would you page on this?"

A useful heuristic (not a rule): if you would never want an alert derived from this line, it is probably not ERROR. Alerts should still prefer **metrics/SLOs**, not log greps — but ERROR volume is often mistakenly wired to pages.

## What to log

**Do log:**

- Process start/stop with **version**, config hash, feature flags summary (not secrets).
- Unrecoverable or final failures with `error.type`, message, and identifiers needed to find the entity.
- Security-relevant events (authn failure rate is a metric; **admin** privilege changes may need an audit log).
- Compensation / saga steps that mutate state across systems (at INFO, with ids).
- Deprecation / "this should never happen" invariant violations (ERROR or WARN with loud clarity).

**Don't log:**

- Every iteration of a loop.
- Successful cache hits at INFO (metric; DEBUG if ever).
- Full HTTP bodies, SQL with bound secrets, JWTs, cookies, `Authorization` headers.
- PII beyond what policy explicitly allows (prefer opaque ids).
- Redundant "success" after every trivial step.

## Request logging patterns

### Prefer: middleware access log OR root span (not both narrating the same thing)

Pick a project convention:

1. **Trace-first**: root span holds method, route, status, duration; logs only for warnings/errors and rare events.
2. **Canonical log line**: one structured INFO/ERROR at the **end** of the request with all fields (Stripe-style). Excellent when traces are weak; still add `trace_id`.

Canonical log line shape:

```
msg=request_completed method=POST route=/v1/checkout status=200 duration_ms=142 order.id=… user.id=… db.queries=3
```

Emit **once** on the way out (defer/middleware), not at start and end.

### Error logging pattern

```text
// Pseudocode — adapt to language
result = doWork(ctx, input)
if result is error:
    // Enrich span
    span.RecordError(err)
    span.SetStatus(Error, …)
    span.SetAttribute("error.type", type(err))

    // Log once if this layer owns the user-visible / queue-visible failure
    logger.ErrorContext(ctx, "checkout failed", "order.id", id, "err", err)
    return err
```

Do **not** also log in `doWork` unless `doWork` swallows the error.

## Hot path logging

On hot paths:

1. **Check level before expensive formatting** (most libraries do this if you use structured fields correctly; avoid `logger.Debug(f"huge {compute()}")` that always computes).
2. Prefer **counters** for "how often did X happen".
3. Use **sampling**: log 1/N successes, all failures.
4. Rate-limit repetitive WARNs (connection pool exhausted should not be 50k lines/sec — metric + occasional WARN).

## Context and correlation

- Pass `context.Context` / request-scoped logger so `trace_id` is automatic.
- Bridges: `otelslog`, OpenTelemetry log appenders, `tracing` layers — prefer official bridges over hand-rolled field injection.
- Background jobs: create a root span/context per job; logs inside must carry that context, not the HTTP request that enqueued them (unless you intentionally link via span links / `messaging` attributes).

## Audit vs operational logs

Keep **security/compliance audit** streams separate when regulators care:

- Immutable, longer retention, stricter access.
- Event names like `role.granted`, `secret.read` with actor, target, reason.
- Do not mix with DEBUG chatter in the same firehose without labels that let you filter.

## Language notes

| Stack | Prefer |
|---|---|
| Go | `log/slog` with JSONHandler; `ErrorContext(ctx, msg, "err", err)`; never `log.Printf` in libraries |
| Python | `structlog` or stdlib logging with JSON formatter; `logger.exception` only when stack matters |
| Rust | `tracing` with `info!`, `warn!`, `error!` and structured fields; `Instrument` futures |
| Node | `pino`; child loggers per request |
| Java | existing facade (SLF4J) + JSON encoder; MDC for trace ids via OTel instrumentation |

## Don't / Do

| Don't | Do |
|---|---|
| Plain-text multi-line stack logs without fields | Structured error + stack in a field / exception recorder |
| Log level by "how surprised I am" | Level by operational severity definitions |
| `catch { log(err) }` then empty | Log only if not rethrowing; else record on span and rethrow |
| Log passwords "masked" as `p***` inconsistently | Never accept secrets into log APIs |
| INFO per Kafka message at 100k/s | Metric per message; log poison pills / final failures |
| Unique free-text messages for the same event | Stable `msg` + fields (queryable, dashboardable) |
