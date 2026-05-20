# Workloads

Every workload in Kubernetes is a `PodSpec` plus a controller that owns it. Pick the controller by **what happens when a pod dies**:

| Controller | What happens on pod death | Use for |
|---|---|---|
| `Deployment` | New pod scheduled; identity is fungible | Stateless services — the default |
| `StatefulSet` | New pod scheduled with the **same** name, hostname, and PVC | Anything with stable identity or per-pod storage — databases, brokers, leader-elected services |
| `DaemonSet` | New pod scheduled **on the same node** | Node agents — log collectors, CNI/CSI plugins, node exporters |
| `Job` | Pod is replaced until success threshold met | One-shot batch work (migrations, backups, one-time ETL) |
| `CronJob` | Spawns a `Job` on schedule | Recurring batch work |
| Bare `Pod` | Nothing — it's gone | Never in production. One-off debugging only. |

`ReplicaSet` is an implementation detail of `Deployment`. Never author one directly.

## PodSpec — the universal building block

Every controller above wraps a `PodSpec`. The template below is the **mandatory shape** — every line is doing real work:

```yaml
spec:
  serviceAccountName: checkout            # explicit, not 'default'
  automountServiceAccountToken: false     # opt in only if the pod needs API access
  terminationGracePeriodSeconds: 30       # tune per workload (see below)

  securityContext:                        # Pod-level
    runAsNonRoot: true
    runAsUser: 65532                      # distroless nonroot
    runAsGroup: 65532
    fsGroup: 65532
    seccompProfile:
      type: RuntimeDefault

  topologySpreadConstraints:              # spread across zones first, then nodes
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app.kubernetes.io/name: checkout
          app.kubernetes.io/instance: checkout-prod

  containers:
    - name: app
      image: ghcr.io/example/checkout@sha256:<digest>
      imagePullPolicy: IfNotPresent

      ports:
        - name: http
          containerPort: 8080
          protocol: TCP

      env:
        - name: PORT
          value: "8080"
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: checkout
              key: log_level

      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          memory: 256Mi                    # always
          # cpu: omitted on purpose — see resources.md

      startupProbe:
        httpGet: { path: /healthz, port: http }
        failureThreshold: 30
        periodSeconds: 2                   # cap at 60s startup budget

      readinessProbe:
        httpGet: { path: /readyz, port: http }
        periodSeconds: 5
        failureThreshold: 3

      livenessProbe:
        httpGet: { path: /healthz, port: http }
        periodSeconds: 10
        failureThreshold: 3

      securityContext:                     # container-level
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: [ALL]
        runAsNonRoot: true

      volumeMounts:
        - name: tmp
          mountPath: /tmp                  # required because rootFS is read-only

  volumes:
    - name: tmp
      emptyDir: {}
```

## Probes — three different questions

| Probe | Question | Failure consequence |
|---|---|---|
| `startupProbe` | "Has this container finished its initial boot?" | Other probes are paused until it passes; once it passes, it never runs again. |
| `readinessProbe` | "Should traffic be sent to this pod right now?" | Pod is removed from Service endpoints. Pod is not restarted. |
| `livenessProbe` | "Is this container alive at all?" | Container is killed and restarted. |

Rules of thumb:

- **Always set a `startupProbe`** for anything with a startup cost > 5 seconds (JVM, big config loads, schema warmup). Without it, the `livenessProbe` will start killing pods during normal boot.
- **`readinessProbe` and `livenessProbe` should hit different endpoints.** `livenessProbe` should be a *cheap, intrinsic* "am I alive" check (process responding). `readinessProbe` is "am I ready to serve" — can include downstream dependency checks.
- **Don't put dependency checks in `livenessProbe`.** If Postgres goes down, you do not want every pod to restart-loop into oblivion.
- **`failureThreshold * periodSeconds` is the budget.** Calibrate. A `failureThreshold: 3` + `periodSeconds: 10` means **30 seconds** between "broken" and "restart."
- **TCP probes for protocols HTTP can't reach** (gRPC over TLS without health service, raw sockets). gRPC services get `grpc:` probes (k8s 1.24+).
- **Exec probes are a last resort.** They fork a process inside the container every interval. Cumulative across thousands of pods, this is a real cost.

## Lifecycle hooks and graceful shutdown

```yaml
containers:
  - name: app
    lifecycle:
      preStop:
        exec:
          command: ["sh", "-c", "sleep 10"]
```

When a pod is being terminated, two things happen **at the same time**:

1. The kubelet sends `SIGTERM` to PID 1.
2. The Service controller removes the pod from endpoints (async; takes ~1s to propagate).

A pod receiving `SIGTERM` may still get new connections for the next ~second. The `preStop sleep` (or an in-app drain on SIGTERM) buys that window. Set `terminationGracePeriodSeconds` to **sleep + actual drain time + buffer**, default ~30s. Pods with long-lived connections (websockets, gRPC streams) need more.

If `terminationGracePeriodSeconds` elapses, kubelet sends `SIGKILL`. Plan for it.

## Init containers and sidecars

```yaml
spec:
  initContainers:                          # run sequentially, must all exit 0 before app starts
    - name: migrate
      image: ghcr.io/example/checkout-migrate@sha256:<digest>
      args: ["up"]

    - name: wait-for-deps                  # native sidecar (1.29+ GA)
      image: ghcr.io/example/sidecar@sha256:<digest>
      restartPolicy: Always                # <- the keyword that makes it a sidecar
      readinessProbe:
        httpGet: { path: /ready, port: 9000 }
```

Native sidecars (1.29 GA) are **init containers with `restartPolicy: Always`**. They start before app containers, stay running for the pod's lifetime, and terminate **after** app containers exit. Use this for service-mesh proxies, log shippers, secret refreshers — anything that needs to outlive the app on shutdown.

Don't use a regular `containers:` entry as a sidecar in new work. The old pattern (sidecar in `containers`, racing with the app) leaks edge cases on termination.

## Update strategy

### Deployments

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0                    # safer default than 25%
  minReadySeconds: 10                      # pod must be ready+steady for this long
  progressDeadlineSeconds: 600
  revisionHistoryLimit: 5                  # capped — don't pile up old ReplicaSets
```

`maxUnavailable: 0` is the right default for production. The cost is rollout time; the benefit is no capacity loss during deploy. Override only when you've deliberately decided 0% capacity headroom is acceptable.

`Recreate` strategy exists. Use it only when the app cannot run two versions simultaneously (in-place DB migrations that change wire format, singletons with cluster-wide locks). It causes downtime by definition.

### StatefulSets

```yaml
spec:
  podManagementPolicy: OrderedReady        # default; Parallel for stateless StatefulSets
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0                         # > 0 to canary the highest-ordinal pods
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenScaled: Retain
```

`partition` is the StatefulSet's canary lever: set to N to update only ordinals ≥ N. Combined with `OrderedReady`, this gives you per-pod rollout control.

`persistentVolumeClaimRetentionPolicy: Retain` is the default and correct for stateful systems — you do not want pod deletion to reap volumes.

### DaemonSets

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 10%
      maxSurge: 0                          # DaemonSets can't surge — one pod per node
```

## Jobs and CronJobs

```yaml
apiVersion: batch/v1
kind: Job
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 3600              # hard kill the Job after 1h
  ttlSecondsAfterFinished: 86400           # GC the Job + its pods 24h after completion
  parallelism: 1
  completions: 1
  podFailurePolicy:                        # 1.31+ — preferred over backoffLimit alone
    rules:
      - action: FailJob
        onExitCodes:
          containerName: app
          operator: In
          values: [42]                     # app-specific "fatal" exit code
      - action: Ignore                     # transient kubelet issues
        onPodConditions:
          - type: DisruptionTarget
```

```yaml
apiVersion: batch/v1
kind: CronJob
spec:
  schedule: "0 3 * * *"                    # nightly at 03:00
  timeZone: "America/Los_Angeles"          # 1.27+ GA; don't rely on cluster TZ
  startingDeadlineSeconds: 300             # if controller missed the trigger by > 5min, skip
  concurrencyPolicy: Forbid                # Allow | Forbid | Replace — Forbid is the safe default
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec: { ... }                          # same shape as Job above
```

Rules:

- **Always set `ttlSecondsAfterFinished`.** Without it, completed Jobs pile up in etcd forever.
- **`concurrencyPolicy: Forbid` is the safe default.** `Allow` enables overlapping runs, which is almost always a bug. `Replace` is fine when the latest run is what matters.
- **`startingDeadlineSeconds` prevents the "controller was down for 6 hours; now it fires 6 hours of missed runs at once" footgun.**
- **`activeDeadlineSeconds` is your runaway-job killswitch.**

## Pod placement — affinity, taints, topology spread

Hierarchy of preference for "spread my pods across zones":

1. **`topologySpreadConstraints`** — explicit, declarative, supports skew. The default.
2. **`podAntiAffinity`** — older, harder-to-reason-about. Use only when the constraint can't be expressed as skew.
3. **`nodeAffinity` / `nodeSelector`** — for "this workload must run on these nodes" (GPU, ARM, dedicated pool).

```yaml
# Pin to a node pool by label
nodeSelector:
  workload-class: bursty

# Tolerate taints (the node has the taint; the pod tolerates it)
tolerations:
  - key: dedicated
    operator: Equal
    value: ingress
    effect: NoSchedule
```

**Taints repel; tolerations permit.** A pod with no toleration can't land on a tainted node. A pod with a toleration *can* land there, but won't necessarily — for "must land here," combine toleration + `nodeAffinity`.

## Quality of Service (QoS)

Set implicitly by what you put in `resources:`:

| QoS class | Trigger | Eviction order |
|---|---|---|
| `Guaranteed` | requests == limits for **all** containers, CPU and memory | Last evicted |
| `Burstable` | requests set but != limits (or only one of them set) | Middle |
| `BestEffort` | no requests, no limits | First evicted |

Most workloads should be `Burstable` (memory: requests == limits, CPU: requests only). Pin to `Guaranteed` only for latency-critical real-time services. `BestEffort` is for unimportant background work — never for user-facing services.

See [resources.md](resources.md) for the requests/limits trade-offs.

## Don't / Do

| Don't | Do |
|---|---|
| Bare `Pod` in production | Wrap in `Deployment` / `StatefulSet` / `Job` / `CronJob` |
| `automountServiceAccountToken: true` for pods that don't talk to the API | `automountServiceAccountToken: false` |
| `securityContext: {}` (default) | Explicit `runAsNonRoot`, `readOnlyRootFilesystem`, dropped caps |
| Only `livenessProbe` set | `startupProbe` + `readinessProbe` + `livenessProbe`, each with intent |
| Same endpoint for `liveness` and `readiness` | Different endpoints answering different questions |
| Dependency checks in `livenessProbe` | Dependency checks in `readinessProbe`; intrinsic checks in `livenessProbe` |
| Sidecar in `containers:` with manual lifecycle hacks | `initContainers:` + `restartPolicy: Always` (native sidecar, 1.29+ GA) |
| `maxUnavailable: 25%` (the kubectl default) | `maxUnavailable: 0`, accept the longer rollout |
| `revisionHistoryLimit: 10` (default) | `revisionHistoryLimit: 5` (or lower) |
| `concurrencyPolicy: Allow` on CronJob | `Forbid` |
| CronJob without `ttlSecondsAfterFinished` | Set it. etcd is not a graveyard. |
| Job without `activeDeadlineSeconds` | Set it. Runaway jobs are real. |
| `podAntiAffinity` for zone spread | `topologySpreadConstraints` with `topology.kubernetes.io/zone` |
| Schedule via `nodeSelector: dedicated=true` alone | Taint the node, tolerate + `nodeAffinity` on the pod |
| Rely on cluster timezone | `spec.timeZone` on CronJob (1.27+ GA) |
| `restartPolicy: Always` on a Job | `OnFailure` (or `Never` if `podFailurePolicy` handles it) |
