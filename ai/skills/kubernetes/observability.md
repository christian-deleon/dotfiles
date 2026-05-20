# Observability

The default observability stack is **Grafana LGTM** — every layer is a Grafana Labs project, and they're designed to interoperate. The single collector across all signals is **Alloy** (the successor to Grafana Agent — also a vendor-neutral OpenTelemetry collector distribution).

| Letter | Backend | Signal |
|---|---|---|
| **L** | Loki | Logs |
| **G** | Grafana | Visualization (dashboards, explore, alerts) |
| **T** | Tempo | Distributed traces |
| **M** | Mimir | Metrics (Prometheus-compatible, horizontally scalable) |
| (+) | Pyroscope | Continuous profiling (CPU, memory, etc.) |

Plus **Alloy** to collect/ship everything to those backends. That's it. No Promtail, no Grafana Agent, no separate Fluentd/Fluent Bit pipeline, no kube-prometheus-stack — Alloy replaces all of them.

The most common AI failure mode here is reaching for **kube-prometheus-stack** by reflex. It's a fine stack, but it's not this user's stack. Don't propose it. If a project already has it, document the migration path but don't introduce parallel pipelines.

## Architecture — one collector, many signals

```
┌─────────────────────────────┐
│  Workloads + control plane  │
└──────────────┬──────────────┘
               │ (metrics, logs, traces, profiles)
               ▼
        ┌──────────────┐
        │    Alloy     │   ← DaemonSet for node-local + per-pod logs
        │              │   ← Deployment for cluster-wide scrape jobs
        └──────┬───────┘
               │ (OTLP, Prometheus remote_write, Loki push, Tempo OTLP)
   ┌───────────┼───────────┬───────────┐
   ▼           ▼           ▼           ▼
 Loki        Tempo       Mimir     Pyroscope
   └───────────┼───────────┴───────────┘
               ▼
            Grafana
```

Two Alloy roles by default:

- **DaemonSet** — runs on every node, scrapes per-node things (kubelet `/metrics/cadvisor`, kubelet `/metrics`, node-local logs from `/var/log/pods`, eBPF profiles via Pyroscope ebpf collector).
- **Deployment** (`Alloy-cluster`) — runs as 2+ replicas, handles cluster-scoped scrape jobs (kube-state-metrics, control plane endpoints, ServiceMonitor / PodMonitor objects, OTLP receivers).

The official **`grafana/k8s-monitoring`** Helm chart wires both up + the core dashboards + the alerts you actually want. Use it as the starting point unless you have a specific reason to assemble the parts yourself.

## Metrics — Mimir + Alloy + Prometheus-shape

Mimir is wire-compatible with Prometheus — anything that writes Prometheus remote-write or scrapes Prometheus endpoints works. The metrics flow:

1. Apps expose `/metrics` (use the Prometheus client lib for the language).
2. A `ServiceMonitor` / `PodMonitor` (Prometheus CRDs, supported by Alloy) tells the cluster what to scrape.
3. Alloy scrapes and remote-writes to Mimir.
4. Grafana queries Mimir via the Prometheus datasource (URL: `http://mimir-querier.<ns>.svc:8080/prometheus`).

### ServiceMonitor / PodMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: checkout
  namespace: checkout
  labels: { release: alloy }                                   # required if the scraper filters by label
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: checkout
      app.kubernetes.io/instance: checkout-prod
  endpoints:
    - port: metrics                                            # named Service port
      interval: 30s
      path: /metrics
      relabelings:
        - action: replace
          sourceLabels: [__meta_kubernetes_pod_node_name]
          targetLabel: node
```

`PodMonitor` is the same shape pointing at pods directly (no Service). Use it for `headless` services or DaemonSets where Service-based scrape doesn't fit.

### Cluster-level scrape targets you should have

| Target | Purpose | Source |
|---|---|---|
| `kubelet` (`/metrics`, `/metrics/cadvisor`, `/metrics/resource`) | Container resource usage, kubelet health | DaemonSet Alloy |
| `kube-state-metrics` | Resource state (Deployments, Pods, PVCs, etc.) as metrics | KSM chart + ServiceMonitor |
| `node-exporter` | Node-level OS metrics (CPU, memory, disk, NIC) | DaemonSet (node-exporter chart, or Alloy's node-local collector) |
| `apiserver` | Control plane health | Cluster-level Alloy (managed clusters expose this; EKS via metrics endpoint) |
| App `/metrics` | App-specific business and runtime metrics | ServiceMonitor / PodMonitor per app |

### Naming and cardinality

The single biggest observability cost is **high-cardinality labels**. Rules:

- **Never label by user ID, session ID, request ID.** That's a log field, not a metric.
- **Label by service name, route template, method, status code, deployment env.** Bounded sets.
- **`exemplars`** can attach a trace ID to a metric sample — that's how you keep cardinality low while still being able to jump from "this latency spike" to "this trace."

If you see a Mimir cost spike, the answer is almost always "kill a label."

## Logs — Loki + Alloy

Loki indexes labels, not log content. The query model is "filter by labels, then grep the chunks." Three Big consequences:

- **Labels matter more than in Mimir.** High-cardinality log labels destroy Loki performance.
- **Don't try to query "every log containing user X."** That's a full-text search problem; Loki isn't built for it. Use labels (`app`, `namespace`, `pod`) to narrow first, then content-grep within.
- **Structured logging makes queries 10x better.** Output JSON to stdout; let Alloy parse it with the `loki.process` block (or use Loki's `json` pipeline stage).

### Pod logs flow

1. Pods write to **stdout/stderr** (do not write to log files inside containers; you lose them on restart).
2. The container runtime writes pod logs to `/var/log/pods/<ns>_<pod>_<uid>/<container>/0.log` on the node.
3. Alloy DaemonSet tails them with `loki.source.kubernetes`, extracts labels from K8s API metadata, parses JSON, pushes to Loki.

Minimum Alloy log pipeline:

```alloy
loki.source.kubernetes "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [loki.process.parse.receiver]
}

loki.process "parse" {
  forward_to = [loki.write.default.receiver]

  stage.json {
    expressions = {
      level = "level",
      msg   = "msg",
      trace_id = "trace_id",
    }
  }

  stage.labels {
    values = { level = "" }
  }
}

loki.write "default" {
  endpoint {
    url = "http://loki-distributor.observability.svc:3100/loki/api/v1/push"
  }
}
```

(Alloy config syntax — not YAML. Lives in a `ConfigMap` referenced by the Alloy chart.)

### Don't log secrets

Obvious but constantly violated. Configure the log pipeline to **redact known sensitive fields** (`Authorization`, `password`, common API key field names) at the Alloy stage, not just in app code. Belt-and-braces.

## Traces — Tempo + OpenTelemetry

Tempo is OpenTelemetry-native (OTLP receiver) and Jaeger/Zipkin-compatible. The architecture:

1. App emits spans via OpenTelemetry SDK (or auto-instrumentation).
2. App sends OTLP to a local Alloy endpoint (`http://alloy.<ns>.svc:4318` for HTTP, `:4317` for gRPC).
3. Alloy batches, samples, enriches, forwards to Tempo.
4. Grafana queries Tempo, joins to logs (via `trace_id` label) and metrics (via exemplars).

### App side — environment variables

The OpenTelemetry SDK respects standard env vars; pass them via the PodSpec:

```yaml
env:
  - name: OTEL_SERVICE_NAME
    valueFrom: { fieldRef: { fieldPath: metadata.labels['app.kubernetes.io/name'] } }
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://alloy.observability.svc:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.namespace=$(POD_NAMESPACE),k8s.pod.name=$(POD_NAME),k8s.node.name=$(NODE_NAME)"
  - name: POD_NAMESPACE
    valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
  - name: POD_NAME
    valueFrom: { fieldRef: { fieldPath: metadata.name } }
  - name: NODE_NAME
    valueFrom: { fieldRef: { fieldPath: spec.nodeName } }
```

### Sampling — head vs tail

- **Head sampling** (in the SDK) — keep N% of traces, decided at start. Cheap, but you miss interesting traces that happen to be in the dropped N%.
- **Tail sampling** (in Alloy / OTel Collector) — buffer for a few seconds, decide based on the **completed trace** (e.g. "keep all traces with errors, 5% of OK traces"). Costs CPU+memory in the collector.

For production, **tail sampling in Alloy** is the right default. Sample on:

- All error traces (`status_code != 0`)
- All slow traces (`duration > 1s` for typical APIs)
- N% (1-5%) of the rest

## Profiles — Pyroscope

Continuous profiling. Two modes:

- **Pull (eBPF, no app changes)** — Alloy DaemonSet runs the `pyroscope.ebpf` component, profiles every process on the node. Zero-instrumentation. Gives CPU profiles.
- **Push (SDK)** — language SDK in the app sends pprof samples to Pyroscope. Higher fidelity, supports memory/lock/goroutine profiles, needs app code change.

eBPF mode is the right default for "we want continuous CPU profiles on everything." Push mode for specific hot paths or non-CPU profile types.

## Correlation — the actual point

The reason LGTM works is that everything correlates by **trace_id** and **k8s.* attributes**:

- A metric query in Grafana → "see exemplars" → jump to a trace.
- A trace → see logs for the same `trace_id` (Loki label).
- A log entry with a `trace_id` → jump to the trace.
- A trace span → see profile for that pod at that time.

For this to work:

- **Apps must propagate W3C trace context** (`traceparent` header). Use the OpenTelemetry SDK; don't hand-roll.
- **Apps must log `trace_id`** in their structured logs (Otel SDK exposes the active span ID; log it).
- **Metrics must emit exemplars** (the Prometheus client libs all support this).
- **Pod labels (`app.kubernetes.io/*`, `k8s.namespace.name`, `k8s.pod.name`) propagate everywhere** — Alloy enriches.

## Alerting

Mimir runs the Prometheus alertmanager-compatible ruler. Author alerts as `PrometheusRule` CRDs:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: { name: checkout-alerts, namespace: checkout, labels: { release: alloy } }
spec:
  groups:
    - name: checkout
      interval: 30s
      rules:
        - alert: CheckoutHighErrorRate
          expr: |
            sum(rate(http_requests_total{namespace="checkout",status=~"5.."}[5m]))
              / sum(rate(http_requests_total{namespace="checkout"}[5m])) > 0.02
          for: 10m
          labels: { severity: page }
          annotations:
            summary: "Checkout 5xx > 2% for 10m"
            runbook_url: "https://runbooks/example/checkout-5xx"
```

Rules:

- **`for:` is non-negotiable.** Alerts without a duration fire on transient spikes and burn out the on-call rotation.
- **SLO-burn-rate alerts** (multi-window, multi-burn-rate) outperform "error rate > N%" alerts. Use Google's [SLO alerting guide](https://sre.google/workbook/alerting-on-slos/) as the template.
- **`severity: page | ticket | info`** label drives routing in alertmanager. Pages wake people; tickets queue.
- **Every page-severity alert has a `runbook_url` annotation.** No exceptions.

## Event log

Kubernetes Events are observability data, not just an API afterthought. Pipe them into Loki:

- Use the `kubernetes_events` source in Alloy, or the [`eventrouter`](https://github.com/heptiolabs/eventrouter) project. Events become Loki streams with full label propagation.
- This is the most useful debugging signal you can have. "What was happening on this node 5 minutes ago?" — Events answer this; pod logs don't.

## What to monitor on day one

The non-negotiable dashboards/alerts every cluster should have:

| Dashboard | Source |
|---|---|
| Cluster CPU/memory utilization, by namespace and node | kube-state-metrics + node-exporter |
| Pod restarts in last 1h (alert: any non-system pod restart > 3 in 1h) | kube-state-metrics |
| OOMKilled events | events stream |
| PVC fill rate (alert: > 80%) | node-exporter + kubelet |
| Ingress 4xx/5xx rate, p99 latency | Traefik metrics |
| Image pull failures | kubelet + events |
| Pending pods > 5 minutes | kube-state-metrics |
| HPA at maxReplicas | kube-state-metrics |
| Certificates expiring < 7 days | cert-manager metrics |

These are starting points; refine per workload. The `grafana/k8s-monitoring` chart ships most of these.

## Don't / Do

| Don't | Do |
|---|---|
| `kube-prometheus-stack` for new work | Grafana LGTM + Alloy (`grafana/k8s-monitoring` chart) |
| Promtail + separate Grafana Agent + Prometheus | One Alloy collector, two roles (DaemonSet + Deployment) |
| Hand-roll Fluentd/Fluent Bit pipeline | Alloy with `loki.source.kubernetes` |
| Label metrics with user IDs / request IDs | Use exemplars for trace correlation; keep labels low-cardinality |
| Plain-text app logs | Structured JSON with `trace_id`, `level`, `msg`; parse via Alloy |
| Write to log files inside containers | stdout/stderr, kubelet handles the rest |
| `OTEL_EXPORTER_OTLP_ENDPOINT` pointing at the backend directly | Point at the local Alloy; Alloy handles sampling/auth/retry |
| Head-sampling 1% in the SDK | Tail-sample in Alloy on errors + slow traces + N% baseline |
| Alerts without `for:` | Every alert has `for:` (5m-15m typical) |
| Alerts on raw error count | SLO-burn-rate alerts |
| Page alerts without `runbook_url` annotation | Mandatory annotation; PR review enforces |
| Ignore the Events stream | Pipe it to Loki via Alloy or eventrouter |
| One giant `loki.process` pipeline | Split per-source; debug-friendly |
| Backup nothing | Grafana dashboards backed by ConfigMaps in git; Mimir/Loki/Tempo are data — back up to S3 |
