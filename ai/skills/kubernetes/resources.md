# Resources, Scaling, and Disruption

Three different scheduling/runtime concerns, often confused:

| Concern | Lever |
|---|---|
| Will the scheduler place the pod? | `requests` |
| Will the kernel kill the pod? | `limits` (specifically memory) |
| Will the kernel throttle the pod? | `limits` (specifically CPU) |
| How many replicas should run? | `replicas`, HPA, KEDA |
| When can replicas be disrupted? | `PodDisruptionBudget` |
| Who gets evicted under pressure? | QoS class (derived from requests/limits), `PriorityClass` |

Get the lever right or the workload misbehaves in ways that look like everything else.

## Requests vs limits

```yaml
resources:
  requests:
    cpu: 100m                                                  # 0.1 cores reserved at scheduling
    memory: 256Mi                                              # 256 MiB reserved
  limits:
    memory: 256Mi                                              # OOMKilled if exceeded
    # cpu: omitted — see below
```

- **`requests`** is what the scheduler subtracts from node capacity. If a node has 4 cores and pods total 3.5 cores of CPU requests, the scheduler won't place a fourth pod that requests 0.6 cores. Requests are the contract.
- **`limits`** is what the kernel enforces at runtime. Exceed memory limit → `OOMKilled` (SIGKILL, immediate). Exceed CPU limit → CFS throttling (the kernel runs your process less, even if cores are idle).

### The CPU limit controversy

**Always set memory limits.** Memory is non-compressible; without a limit, the pod can balloon and the kubelet evicts arbitrary pods.

**CPU limits are conditionally a footgun.** The Completely Fair Scheduler (CFS) implements CPU limits via quota+period, and the period is short (default 100ms). A spiky workload that briefly bursts above its limit gets throttled the same as one that consistently exceeds it — even when the node has idle cores. Common symptom: P99 latency spikes that vanish when the limit is removed.

Two pragmatic stances:

1. **Set both memory and CPU limits, but set CPU limit generously** (e.g. 2x request) and rely on the request to bin-pack. Safer in multi-tenant clusters where one workload running away can starve others.
2. **Set memory limit, omit CPU limit.** The pod can use all idle CPU on the node. Requires trusting workloads + having capacity headroom. Common in single-team clusters where the cost of unfair CPU share is lower than the cost of latency spikes.

Either is defensible. The wrong answer is "set CPU limit equal to request and call it a day" — that's the default that bites.

If you set CPU limits, monitor `container_cpu_cfs_throttled_periods_total` from cAdvisor. Throttling > 0% is normal; throttling consistently > 1-2% on a latency-sensitive service is the symptom of a too-low limit.

### Requests for both is required, limits are conditional

| | Pattern | When |
|---|---|---|
| **Memory** | `requests == limits` | Default for most workloads. QoS Guaranteed (for that resource). |
| **Memory** | `requests < limits` | "I usually need X but can burst to Y." Risk: pod gets OOMKilled at Y. |
| **CPU** | `requests` set, no limit | Default for latency-sensitive services in trusted-workload clusters |
| **CPU** | `requests == limits` | Guaranteed QoS. Required for some node configurations (CPU pinning, dedicated CPUs). |
| **CPU** | `requests < limits` | "Bursty" workloads — let burst happen but cap it |
| **CPU** | Both unset | BestEffort QoS. Don't. |
| **CPU** | Limit only, no request | Falls back to request == limit. Workable but unclear; set both explicitly. |

For the full QoS-class implications, see [workloads.md](workloads.md).

## LimitRange — namespace-default resource policy

Set defaults so authors don't forget. Kyverno can enforce, but `LimitRange` lets the API server fill in defaults:

```yaml
apiVersion: v1
kind: LimitRange
metadata: { name: defaults, namespace: checkout }
spec:
  limits:
    - type: Container
      default:                                                 # applied if container has no limits
        cpu: 500m
        memory: 512Mi
      defaultRequest:                                          # applied if container has no requests
        cpu: 100m
        memory: 128Mi
      max:                                                     # reject pods exceeding these
        cpu: 4
        memory: 8Gi
      min:
        cpu: 10m
        memory: 16Mi
```

`LimitRange` is useful safety net, but **don't let it be the only thing**. Explicit requests/limits per workload beat namespace defaults.

## ResourceQuota — namespace-wide capacity caps

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: checkout-quota, namespace: checkout }
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    persistentvolumeclaims: "10"
    requests.storage: 500Gi
    pods: "50"
    services.loadbalancers: "2"                                # cap LB creation
    count/deployments.apps: "20"
```

Use in multi-tenant clusters to keep one namespace from consuming the cluster. Often paired with a `LimitRange` so individual pods can't exceed allowable defaults.

## HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: checkout, namespace: checkout }
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: checkout
  minReplicas: 3
  maxReplicas: 30
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60                               # target 60% of request
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75
  behavior:                                                    # crucial — defaults are wrong for most workloads
    scaleUp:
      stabilizationWindowSeconds: 0                            # scale up immediately
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30                                    # double every 30s if needed
        - type: Pods
          value: 4
          periodSeconds: 30
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300                          # wait 5min before scaling down
      policies:
        - type: Percent
          value: 25
          periodSeconds: 60                                    # at most 25% removed per minute
      selectPolicy: Max
```

Rules:

- **Always set `behavior.scaleDown.stabilizationWindowSeconds`**. The default (300s as of 1.30) is reasonable, but the *default behavior policies* are aggressive and will cause flapping under bursty load. Set them explicitly.
- **Scale-up should be fast, scale-down slow.** A bad latency spike is worse than a bit of overcapacity for a few minutes.
- **HPA needs `metrics-server` installed** for resource metrics. For anything else, add KEDA.
- **CPU+memory together** is risky — the HPA picks the **higher** of the two recommended counts, but the two often disagree. Pick one as primary, use the other as a guard.

### KEDA — event-driven autoscaling

For anything that isn't CPU or memory — queue depth, Kafka lag, Prometheus query, cron, HTTP request rate — use KEDA. KEDA renders a normal HPA under the hood; you author a `ScaledObject`:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: checkout-worker, namespace: checkout }
spec:
  scaleTargetRef:
    name: checkout-worker                                      # Deployment to scale
  minReplicaCount: 1
  maxReplicaCount: 50
  pollingInterval: 15
  cooldownPeriod: 300
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://mimir-querier.observability.svc:8080/prometheus
        query: sum(rate(orders_pending[2m]))
        threshold: "10"
    - type: kafka
      metadata:
        bootstrapServers: kafka.kafka.svc:9092
        consumerGroup: checkout-workers
        topic: orders
        lagThreshold: "100"
```

KEDA also supports **scale-to-zero** (`minReplicaCount: 0`) — invaluable for cost on event-driven workloads. Pair with a queue/HTTP-based activation trigger; the activator wakes pods on the first request.

### Vertical Pod Autoscaler (VPA)

VPA recommends or applies resource request/limit changes based on observed usage. Three modes:

- **`Off`** — recommendations only, written to `status.recommendation`. Use this everywhere as a baseline; eyeball recommendations during sizing reviews.
- **`Initial`** — applies recommendations at pod creation. Safe; doesn't disturb running pods.
- **`Auto`** — evicts and recreates pods with new sizes. **Conflicts with HPA on the same resource.** Don't enable on services with HPA on CPU/memory.

The 1.27+ **in-place pod resize** (alpha→beta) lets the kubelet update requests/limits without restarting the pod. VPA's `Auto` mode plus in-place resize is the future, but treat it as experimental for now.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: { name: checkout, namespace: checkout }
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: checkout
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: '*'
        minAllowed: { cpu: 50m, memory: 64Mi }
        maxAllowed: { cpu: 2, memory: 4Gi }
        controlledResources: ["cpu", "memory"]
```

## PodDisruptionBudget

PDBs limit voluntary disruptions (drain, eviction). They don't help with crashes or node failures.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: checkout, namespace: checkout }
spec:
  minAvailable: 2                                              # or maxUnavailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: checkout
      app.kubernetes.io/instance: checkout-prod
  unhealthyPodEvictionPolicy: AlwaysAllow                      # 1.27+; default is IfHealthyBudget
```

Rules:

- **`replicas > 1` workloads get a PDB.** No exceptions for stateless services.
- **`minAvailable` for stateful** (always have N healthy pods), **`maxUnavailable` for stateless** (allow K to roll at once).
- **`minAvailable: 50%`** or **percentages** are fine for replicas that scale.
- **`unhealthyPodEvictionPolicy: AlwaysAllow`** lets crashed pods be evicted from a node being drained — without this, an unhealthy pod can block node maintenance. The default (`IfHealthyBudget`) is conservative; `AlwaysAllow` is usually correct.
- **PDB and HPA need to be coherent.** If your HPA's `minReplicas` is 2 and your PDB is `minAvailable: 2`, you cannot ever drain a node hosting any replica without scaling first. Use percentages.

## PriorityClass

Pods with higher priority preempt lower-priority pods when the scheduler can't fit them. Use sparingly:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: production-critical }
value: 1000000
globalDefault: false
description: "Production-critical workloads; preempt-allowed."
preemptionPolicy: PreemptLowerPriority
```

Built-in classes:

- `system-cluster-critical` (2,000,000,000) — control plane
- `system-node-critical` (2,000,001,000) — node-critical daemons (CNI, log shippers)

Application priority bands:

| Tier | Value range | Use |
|---|---|---|
| `critical` | 1,000,000 | User-facing prod that must never be evicted by other apps |
| `high` | 100,000 | Standard prod |
| `normal` | 10,000 | Default for most workloads |
| `low` | 100 | Best-effort batch (preempted first under pressure) |

Set `globalDefault: true` on one class — that's the namespace default for unannotated pods.

## Topology spread

Already covered in [workloads.md](workloads.md). The recap:

- **`topologySpreadConstraints`** is the default for spreading replicas across failure domains.
- **`whenUnsatisfiable: DoNotSchedule`** is strict — won't place if spread can't be honored. Use for true HA requirements.
- **`whenUnsatisfiable: ScheduleAnyway`** is best-effort — places anyway if necessary. Use for less-critical workloads.
- **Multi-level spread**: spread across zones first, then across nodes within a zone — two constraints with different `topologyKey`s.

## Resource hints that actually move the needle

| Symptom | Probable cause | Fix |
|---|---|---|
| Pod stuck `Pending`, message "insufficient cpu/memory" | Sum of requests on every node exceeds capacity | Scale node pool, or reduce requests |
| P99 latency spikes that vanish when CPU limit removed | CFS throttling | Raise limit ≥ 2x request, or remove |
| OOMKilled at a low memory level | App allocates above limit; or container_memory_working_set_bytes spike | Raise memory limit; profile the app |
| HPA flapping between two replica counts | `scaleDown.stabilizationWindowSeconds` too low | 300s minimum |
| HPA never scales up | `metrics-server` not installed, or metrics > target by a tiny margin | Verify `kubectl top pods` works; check HPA target threshold |
| Replicas all on one node | No `topologySpreadConstraints`, or anti-affinity too lax | Add explicit zone+node spread |
| Eviction storm under memory pressure | All pods are `BestEffort` (no requests) | Set requests on everything |

## Don't / Do

| Don't | Do |
|---|---|
| Forget `requests` (BestEffort QoS) | Always set requests on every container |
| `cpu: limit == request` reflexively | Limit > request, or omit limit, with eyes open about the trade-off |
| `memory: requests < limits` (burstable memory) without monitoring | Track OOMKills; `requests == limits` is safer for most |
| `LimitRange` as the only resource policy | Explicit per-workload requests/limits; LimitRange as safety net |
| `replicas > 1` without a PDB | PDB always; `minAvailable: 50%` for scaling workloads |
| HPA with default `behavior` | Explicit `scaleUp`/`scaleDown` policies |
| `minReplicas == maxReplicas` in HPA | If it doesn't scale, don't use HPA |
| HPA + VPA `Auto` on the same resource | Pick one — HPA for replicas, VPA-`Off` for sizing recommendations |
| KEDA for CPU/memory scaling | Use plain HPA; KEDA for events, queues, custom metrics, scale-to-zero |
| Custom `PriorityClass` everywhere | Three or four tiers; `globalDefault: true` on `normal` |
| `topologySpreadConstraints` with `whenUnsatisfiable: DoNotSchedule` on every workload | Reserve it for actual HA-required services; ScheduleAnyway is fine elsewhere |
| Quota only on CPU/memory | Quota PVCs, LoadBalancers, NodePorts too — they cost real money |
| Treat throttling as normal at any percentage | Spike investigation when consistently > 1-2% on latency-sensitive services |
