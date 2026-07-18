# Traces

A **trace** is the causal story of one unit of work across process boundaries. A **span** is one operation inside that story: timed, named, attributed, optionally nested. Traces answer *where time went* and *what failed on this path*. They are the backbone of modern debugging; metrics tell you *that* something is wrong, traces (and correlated logs) tell you *which* request and *why*.

## Mental model

```
Trace (trace_id)
└── Span: POST /v1/checkout          [SERVER, root]
    ├── Span: SELECT orders           [CLIENT, db]
    ├── Span: POST stripe/charges     [CLIENT, http]
    │   └── (remote service's spans under same trace_id)
    └── Span: publish order.completed [CLIENT, messaging]
```

**Wide event / canonical request span:** put as many useful dimensions as possible on the **root** (or "main") span so a single record describes the request: user, tenant, route, status, build, feature flags, cart value bucket, outcome. Child spans decompose latency; the root span is the product analytics / incident slice surface.

## When to create a span

| Create a span | Skip a span |
|---|---|
| Inbound RPC/HTTP/message handler (root) | Pure in-memory getters/setters |
| Outbound HTTP, gRPC, DB, cache, queue | Tight loop iterations (use metrics) |
| Significant internal phases (auth, price, render) when they can be slow or fail independently | Every private helper |
| Retries (per attempt **or** clear resend attributes — follow OTel HTTP resend rules) | Spans that never finish (missing end) |
| Async fan-out branches you need to distinguish | Noise that doubles cardinality of span names |

Rule of thumb: if you would ever ask "was **this** step slow?" or "did **this** dependency fail?", it deserves a span (or a span event). If you would never look at it except while single-stepping in a debugger, it does not.

## Span naming

Follow OpenTelemetry:

- **Low cardinality.** Names are identities, not log lines.
- HTTP server: `{method} {route}` → `GET /users/{id}` (route template, not `/users/123`).
- HTTP client: same idea with peer route template if known; else `{method}`.
- DB: often `{db.operation} {db.collection}` or the library's semconv name — **not** full SQL with literals.
- Internal: `checkout.authorize_payment`, `inventory.reserve` — dotted stable names.

**Never** put user ids, emails, or free-form URLs in the span **name**. Put them in attributes.

## Span kind

| Kind | Use |
|---|---|
| `SERVER` | Inbound request handling |
| `CLIENT` | Outbound dependency call |
| `PRODUCER` | Sending a message (async) |
| `CONSUMER` | Processing a message |
| `INTERNAL` | In-process subunits |

## Attributes

### What goes on spans (high cardinality OK)

Prefer OTel semantic conventions when they exist:

| Area | Examples |
|---|---|
| HTTP | `http.request.method`, `http.route`, `http.response.status_code`, `url.scheme` |
| Server/client | `server.address`, `server.port`, `network.peer.address` |
| DB | `db.system.name`, `db.namespace`, `db.operation.name`, `db.collection.name` |
| Messaging | `messaging.system`, `messaging.destination.name`, `messaging.operation.type` |
| Error | `error.type` |
| End-user (careful) | `user.id` (opaque), `enduser.id` — avoid email/PII unless policy allows |
| Business | `app.order.id`, `app.tenant.id`, `app.payment.provider` — **prefix** proprietary fields |
| Deploy | `service.version`, `service.instance.id` (usually Resource, not per-span) |

### Resource vs span attributes

| Resource (process-wide) | Span (per request) |
|---|---|
| `service.name`, `service.version` | `http.route`, `user.id` |
| `deployment.environment` | `order.id`, feature flag evaluation |
| K8s pod/node/cluster | Per-request outcome |

Set Resource once at SDK startup. Do not re-set `service.name` on every span differently.

### Wide-event attribute checklist (root span)

Pack when known (non-exhaustive):

- Request: method, route, status, duration (automatic), request id, user-agent class
- Identity: tenant/org id, user id (opaque), auth method
- Build: version, git SHA (resource or span)
- Product: feature flags that affected the path, plan tier, country/region **if** low-risk
- Dependencies summary: optional counts (`db.queries`, `cache.misses`) as attributes set at end
- Outcome: `app.checkout.result=success|declined|error`

Hundreds of dimensions are fine on events/spans in OLAP-style backends; they are **not** fine as Prometheus labels.

## Status and errors

Per OTel HTTP conventions (generalize):

| Situation | Span status |
|---|---|
| Success 2xx/3xx | Unset (OK) |
| Server span + 4xx | **Unset** (client's problem) unless you know better |
| Client span + 4xx | Error (caller failed to get a successful response) — context-dependent |
| 5xx / network failure / timeout | Error |
| Intentional cancel | Unset; do not set `error.type` for pure cancellation |

Always:

- `span.RecordError(err)` (or language equivalent) for failures you attach.
- `error.type` = stable class (`TimeoutError`, `PostgresError`, `stripe.CardError`), not the full message.
- Do not put stack traces in attributes that explode cardinality across backends that index them poorly — use the exception event API when available.

## Context propagation

- **W3C Trace Context** (`traceparent`, `tracestate`) for HTTP.
- Instrument outbound clients (or use auto-instrumentation). Custom `X-Request-Id` alone is **not** a trace parent (use both: request id as attribute, traceparent for graph).
- For queues: inject context into message headers/metadata; extract on consume; use PRODUCER/CONSUMER kinds; consider **span links** when a consumer batch relates to many parents.
- Do not put PII or auth tokens in **baggage**. Baggage is propagated widely and easily logged by accident.

## Sampling

| Strategy | Pros | Cons |
|---|---|---|
| **Head** (e.g. 5% at start) | Cheap, simple, consistent traces | Misses rare errors if not sampled |
| **Tail** (decide after complete) | Keep 100% errors + slow + N% OK | Stateful collector cost |
| **Parent-based** | Honors upstream decision | Bad upstream ⇒ bad local |

Production default for high volume:

1. Parent-based + reasonable head ratio for pure-OK traffic **or**
2. Tail sampling in the collector: `errors OR latency > threshold OR random 1–5%`.

Never "sample 1% head only" on a payment service without a guaranteed error keep path.

App code should still **create** spans; sampling drops export, not the API. Avoid huge attributes on spans you create millions of times per second even if sampled — attribute serialization can still cost.

## Span events vs child spans vs logs

| Mechanism | Use when |
|---|---|
| **Child span** | Timed sub-operation with its own duration/failure |
| **Span event** | Point-in-time annotation ("retry", "cache miss") without meaningful duration |
| **Log** | Operator narrative, large detail, or systems without span UI access |

Prefer span events over DEBUG logs for things that must sit on the timeline of a specific request.

## Zero-code vs code-based

| Zero-code (agent/auto) | Code-based |
|---|---|
| Framework HTTP, DB drivers, gRPC | Business attributes, domain operations |
| Quick coverage at edges | Critical path outcomes |
| Can miss custom protocols | You own naming |

Use **both**: auto for edges, manual for domain. Manual spans without auto still need the SDK + exporter configured.

## Anti-patterns

| Bad | Fix |
|---|---|
| New span for every function in a call chain | Span only boundaries + slow phases |
| Span name includes `user=alice` | Attribute `user.id` |
| Forgot `span.end()` / not using `defer`/try-with-resources | Always end in finally/defer |
| Root span per DB call with no request parent | Attach to request context |
| Broken context across goroutine/thread/async | Pass context explicitly; use language OTel async helpers |
| 100% export of health-check traces | Exclude probes or sample them to near-zero |
| Client and server both invent incompatible attributes | Follow semconv |

## Minimal instrumentation sketch

```text
// Inbound middleware (conceptual)
ctx, span = tracer.Start(ctx, "POST /v1/checkout", SERVER)
defer span.End()
span.SetAttributes(http.method, http.route, …)

// Outbound
ctx, span = tracer.Start(ctx, "POST", CLIENT)
span.SetAttributes(server.address=…, http.request.method=POST)
// … do call …
span.SetAttributes(http.response.status_code=…)
if err: span.RecordError(err); span.SetStatus(Error)

// Domain
span.SetAttributes(app.order.id=…, app.checkout.result=…)
```

Wire logs with the same `ctx` so `trace_id` appears automatically.

## Don't / Do

| Don't | Do |
|---|---|
| Trace as a standalone product with no log/metric correlation | Same `service.*` resource + trace ids in logs + exemplars |
| Hand-roll trace IDs | OTel SDK + W3C propagation |
| Sample away all failures | Tail-keep errors and high latency |
| Attributes with huge payloads (full bodies) | Sizes, hashes, content-types; sample bodies to debug builds only |
| One giant span for the whole process lifetime | One span per unit of work |
