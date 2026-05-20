# Debugging

Kubernetes debugging is a triage tree. Most cluster problems fall into a small number of buckets, each with a distinct signal. Start with the signal, not the kubectl command.

The first command, almost always, is `events`:

```bash
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -40
```

If you have the `kubernetes` MCP server, prefer `mcp__kubernetes__events_list` — same data, lives in the conversation. Events tell you what the API server has been *trying* to do, which is usually what you need to know.

## Pod statuses — what each one means

| Status | Meaning | First check |
|---|---|---|
| `Pending` | Scheduler hasn't placed the pod | `kubectl describe pod` — look at the bottom for scheduling errors |
| `ContainerCreating` | Pod placed, kubelet pulling image / mounting volumes | Image pull, volume attach, secret/configmap missing |
| `CrashLoopBackOff` | Container starts, exits, restarts, exits, ... | Container logs (current AND `--previous`) |
| `Error` | Container exited non-zero, not configured to restart | Same as CrashLoopBackOff |
| `OOMKilled` (in `lastState`) | Kernel killed it for exceeding memory limit | Raise memory limit; or fix the leak |
| `ImagePullBackOff` / `ErrImagePull` | Image can't be pulled | Bad tag, bad registry creds, network |
| `Init` | Init container still running | `kubectl logs <pod> -c <init-container>` |
| `Terminating` (stuck) | Pod deletion blocked by finalizer or stuck volume | `kubectl get pod -o yaml` and look at finalizers |
| `Completed` | Pod ran to completion (Jobs) | Normal for Jobs; check `kubectl get job` for the parent |
| `Evicted` | Kubelet evicted the pod under pressure | Node pressure — check `kubectl describe node` |

## Pending pods

Pod status is `Pending`. Run:

```bash
kubectl describe pod <name>
```

Look at the **Events** section. Common patterns:

| Event message | Cause | Fix |
|---|---|---|
| `0/N nodes are available: N Insufficient cpu` | No node has enough CPU left | Scale node pool; reduce requests |
| `0/N nodes are available: N Insufficient memory` | Same, memory | Same |
| `0/N nodes are available: N node(s) had untolerated taint` | Pod doesn't tolerate the taint on the only-suitable nodes | Add `tolerations`; or remove the taint |
| `0/N nodes are available: N node(s) didn't match Pod's node affinity` | `nodeSelector` / `nodeAffinity` doesn't match any node | Fix the selector or label nodes |
| `0/N nodes are available: N had volume node affinity conflict` | PV is in zone A, pod can't be placed in zone A | `volumeBindingMode: WaitForFirstConsumer` on the StorageClass (see [storage.md](storage.md)) |
| `0/N nodes are available: N didn't match pod topology spread constraints` | `whenUnsatisfiable: DoNotSchedule` can't be satisfied | Loosen the constraint, or scale to allow spread |
| `Failed to create pod sandbox` | Container runtime can't start the sandbox — usually CNI/IP exhaustion | Check CNI logs; node pod-CIDR may be exhausted |

A useful one-liner to find which nodes the pod *can't* go on and why:

```bash
kubectl describe pod <name> | grep -A 50 "Events:"
```

## CrashLoopBackOff

```bash
# Current logs (probably empty if it crashed instantly)
kubectl logs <pod> -c <container>
# Previous container's logs — almost always what you want
kubectl logs <pod> -c <container> --previous --tail=200
# Why was it restarted?
kubectl describe pod <pod> | grep -A 10 "Last State"
```

Things to look at:

- `Last State: Terminated, Reason: <X>, Exit Code: <N>`
  - `Exit Code: 0` — clean exit; probably misconfigured `restartPolicy`
  - `Exit Code: 1`, `2`, `137`, `139`, `143` — see table below
  - `Reason: OOMKilled` — memory limit too low
  - `Reason: Error` — generic crash; check logs
- **Probes**: `livenessProbe` failures cause restart. Check `Last State` for the probe trigger.
- **Init container failed**: a failed init container blocks the pod indefinitely. Inspect init logs separately.

| Exit code | Meaning |
|---|---|
| 0 | Clean exit (often: app finished, not designed to be long-lived) |
| 1 | Uncaught application error |
| 2 | Misuse of shell builtin or unhandled CLI flag |
| 125 | Docker daemon error (rare in K8s; usually means container couldn't start) |
| 126 | Container command found but not executable |
| 127 | Container command not found |
| 137 | SIGKILL (128 + 9) — kubelet OOM kill, or `terminationGracePeriodSeconds` exceeded |
| 139 | SIGSEGV (128 + 11) — segfault |
| 143 | SIGTERM (128 + 15) — graceful shutdown; only "bad" if it happened unexpectedly |

If the container crashes **before producing any logs**:

```bash
kubectl run dbg --rm -it --image=<same-image> --restart=Never --command -- sh
# manually run the entrypoint and see what blows up
```

## ImagePullBackOff / ErrImagePull

```bash
kubectl describe pod <pod> | grep -A 5 "Events:"
```

Common causes:

| Symptom | Cause |
|---|---|
| `manifest for X not found` | Tag doesn't exist in registry |
| `unauthorized` / `authentication required` | Missing or wrong `imagePullSecrets` |
| `connection refused` / `i/o timeout` | Registry unreachable from the node (firewall, DNS) |
| `name unknown` | Misspelled image name or wrong registry |
| `rate limit` | Docker Hub anonymous rate limit — switch to authenticated pulls, or mirror images |

Verify the image exists from the **node's perspective** (use a debug pod on the right node):

```bash
kubectl debug node/<node> -it --image=ghcr.io/<image-debug-tool>
```

For private registries: check the `imagePullSecret` is on the ServiceAccount (see [security.md](security.md)).

## OOMKilled

```bash
kubectl describe pod <pod> | grep -A 5 "Last State"
# Look for: Reason: OOMKilled, Exit Code: 137
```

If you see `OOMKilled`:

1. **Verify it's really OOM and not the app**. Some apps catch SIGTERM and exit 137 themselves.
2. **Check actual memory usage** of similar pods:
   ```bash
   kubectl top pods -n <ns> --containers
   ```
3. **Raise the memory limit** if usage looks legitimate.
4. **Profile the app** if usage is unexpectedly high. Pyroscope (memory profile) or `pprof` for Go.

Don't reflexively raise limits. A persistent leak grows until it kills the cluster; raising the limit just delays the problem.

## Stuck `Terminating`

Pod has been `Terminating` for minutes/hours.

```bash
kubectl get pod <name> -o yaml | yq '.metadata.finalizers, .metadata.deletionTimestamp'
```

If finalizers are listed, **a controller is supposed to remove them** before the pod can actually delete. Two failure modes:

- The controller is down or stuck → fix the controller.
- The finalizer's owning controller is gone → manually remove:
  ```bash
  kubectl patch pod <name> --type='merge' -p '{"metadata":{"finalizers":null}}'
  ```
  **Don't do this routinely** — finalizers exist for a reason (e.g. volume detach, external cleanup). Remove only when you've confirmed the cleanup is done or doesn't matter.

If no finalizers but still terminating: the kubelet is having trouble with the pod (volume detach hanging, container runtime stuck). Check node:

```bash
kubectl describe node <node>
journalctl -u kubelet -n 500 --no-pager
```

## Networking debugging

### Can the pod reach what it thinks it can reach?

The two-step check:

1. **Does the Service exist and have endpoints?**
   ```bash
   kubectl get svc <svc> -n <ns>
   kubectl get endpointslices -l kubernetes.io/service-name=<svc> -n <ns>
   ```
   If the EndpointSlice has no addresses, the Service `selector` matches no Pods (or matched Pods aren't ready).

2. **Is the call actually reaching the Service?**
   Drop a debug pod into the same namespace and try:
   ```bash
   kubectl run dbg --rm -it -n <ns> --image=nicolaka/netshoot --restart=Never -- bash
   # inside the pod:
   nslookup <svc>
   curl -v http://<svc>:<port>/health
   ```
   `nicolaka/netshoot` is the standard "everything network-debug" image — has `curl`, `dig`, `tcpdump`, `traceroute`, `mtr`, `iperf3`, `nmap`, all of it.

### DNS not resolving

```bash
# from inside a debug pod
nslookup kubernetes.default
nslookup <svc>.<ns>.svc.cluster.local
# check the /etc/resolv.conf the pod is using
cat /etc/resolv.conf
# is CoreDNS healthy?
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=200
```

Common: `ndots: 5` default causes 5+ DNS lookups for every external name. See [networking.md](networking.md) for the fix.

### NetworkPolicy blocking

If you've enabled default-deny NetworkPolicy and traffic stops working, the policy is the suspect:

```bash
# Cilium-specific: see what flows are being dropped
hubble observe --pod <ns>/<pod> --verdict DROPPED
```

For non-Cilium CNIs, drop policies and re-add incrementally to find the bad rule.

### Ingress not routing

```bash
kubectl get ingress -n <ns> <name>
kubectl describe ingress -n <ns> <name>                        # look for events from the controller

# For Traefik IngressRoute:
kubectl get ingressroute -n <ns> <name>
kubectl describe ingressroute -n <ns> <name>

# Traefik logs (if not noisy already)
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=200
```

Common: TLS Secret missing or in the wrong namespace; backend Service has no endpoints; middleware references the wrong namespace (`<ns>-<middleware>@kubernetescrd` namespace-qualified syntax).

## Ephemeral debug containers

The right tool for "the pod is running but I need to look inside" — without killing or restarting the pod (1.25+ GA):

```bash
# Attach a debug container to a running pod
kubectl debug -it <pod> -n <ns> --image=nicolaka/netshoot --target=<container-name>

# Useful for distroless images that don't have a shell
kubectl debug -it <pod> -n <ns> --image=nicolaka/netshoot --target=<container-name> --share-processes

# Debug a node — runs a pod with hostPID, hostNetwork, /host mount
kubectl debug node/<node> -it --image=nicolaka/netshoot
```

The `--target` flag makes the debug container share the target container's process namespace; you can `ps aux` and see the actual app's processes.

`--share-processes` works at the pod level — share `pid` namespace across all containers in the pod.

For distroless / static images this is the only way to get a shell into the running pod without rebuilding.

## API server / control plane

For cluster-level issues (whole namespaces broken, kubectl returning errors):

```bash
# Is the API server reachable?
kubectl cluster-info
kubectl version --short

# What's the API server saying?
# (For self-managed: journalctl -u kube-apiserver or rke2-server)
journalctl -u rke2-server -f
# For EKS / GKE / AKS: cloud console / log aggregation

# Are controllers running?
kubectl get pods -n kube-system
```

For RKE2/K3s logs:

```bash
sudo journalctl -u rke2-server -n 500
sudo journalctl -u rke2-agent -n 500
sudo journalctl -u k3s -n 500
sudo journalctl -u k3s-agent -n 500
```

## Node-level debugging

```bash
kubectl describe node <node>                                   # conditions, taints, capacity, allocations
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node>
kubectl top node                                               # live CPU/memory
```

Node conditions to know:

| Condition | Means |
|---|---|
| `Ready: True` | Kubelet is happy |
| `MemoryPressure: True` | Node is out of memory; eviction in progress |
| `DiskPressure: True` | Node disk full or near-full; eviction in progress |
| `PIDPressure: True` | Out of PIDs (rare but happens with PID-leak bugs) |
| `NetworkUnavailable: True` | CNI hasn't initialized the node network |

For deeper node inspection, SSH (or `kubectl debug node/<node>`) and look at:

- `journalctl -u kubelet -n 500`
- `crictl ps`, `crictl logs <id>` (containerd)
- `df -h` (`/var/lib/containerd`, `/var/lib/kubelet` get full first)
- `dmesg | tail` (kernel OOM, panic messages)

## Resource visibility — the queries you'll run a thousand times

```bash
# All pods that aren't Running or Completed
kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded

# Pods that are restarting frequently
kubectl get pods --all-namespaces --sort-by='.status.containerStatuses[0].restartCount' \
  | tail -20

# What's using node X?
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node> \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory

# Image inventory
kubectl get pods --all-namespaces -o jsonpath="{range .items[*]}{range .spec.containers[*]}{.image}{'\n'}{end}{end}" \
  | sort -u

# Pending PVCs
kubectl get pvc --all-namespaces --field-selector=status.phase=Pending
```

## Common patterns and their non-obvious causes

| Symptom | Less obvious cause |
|---|---|
| `Pending` pod with no scheduling error | `PriorityClass` is preempting it back into Pending repeatedly |
| `CrashLoopBackOff` on a known-working image | A new ConfigMap/Secret with bad data was mounted; restart picks it up immediately |
| Service has endpoints but traffic doesn't reach pods | NetworkPolicy in the destination namespace; check Cilium Hubble |
| Pod runs locally but not in cluster | `runAsNonRoot: true` + image expects root; or `readOnlyRootFilesystem: true` + app writes to `/var/cache` |
| Liveness probe failures during deploy | `startupProbe` missing — liveness fires during legitimate boot |
| Cluster suddenly evicts everything | Node `DiskPressure: True` — check `df -h` on nodes |
| `dial tcp ... no such host` from a pod | DNS hasn't loaded; or `ndots: 5` is searching wrong domains first |
| HPA never scales | metrics-server not installed; or `kubectl top pods` doesn't work |
| Helm install fails with "release already exists" | Old release in Failed state; `helm uninstall` first or use `--force` (defer to `helm` skill) |
| `kubectl exec` returns "OCI runtime error" | Container has no shell (distroless) — use `kubectl debug` instead |
| Volume stuck `Attaching` after pod reschedule | Cloud-provider detach didn't complete — force-detach via cloud API |
| `mkdir: cannot create directory '/var/log': Read-only file system` | `readOnlyRootFilesystem: true` working as intended; mount `emptyDir` for writable paths |
| `connection refused` to service even with endpoints | App listening on `127.0.0.1` instead of `0.0.0.0` — common in dev configs accidentally shipped |

## When to escalate

Some things aren't debuggable from inside the cluster:

- **etcd corruption** — `etcd` returns inconsistent reads, or `kubectl` hangs randomly. Restore from snapshot.
- **API server certs expired** — RKE2/K3s rotate automatically; vanilla kubeadm clusters can hit this. `journalctl -u kubelet` will show TLS errors.
- **Kernel-level networking bugs** — overlay packets dropped at the NIC. `tcpdump` on the node confirms. Kernel/CNI version bump.
- **CSI driver wedged** — volumes won't detach because the driver is in a bad state. Restart the CSI controller pods; if that doesn't work, restart the node.

For these, get cluster admin help. The MCP server can confirm the symptom; the fix is outside the API.

## Don't / Do

| Don't | Do |
|---|---|
| Run `kubectl logs` without checking `--previous` after a crash | `--previous` is usually where the answer is |
| Skip `kubectl describe` and jump to logs | `describe` shows scheduling, probes, mount, image-pull, and event history in one place |
| Patch out finalizers reflexively | Investigate why the owning controller isn't removing them |
| Raise memory limits without confirming the workload usage | `kubectl top` first; profile if usage is unexpectedly high |
| Drop default-deny NetworkPolicy to "fix" connectivity | Use Hubble (Cilium) or add specific allow rules |
| `kubectl exec` distroless and wonder why it fails | `kubectl debug -it --target=<container>` with a debug image |
| Trust `kubectl top` if it returns zero | Verify `metrics-server` is installed and Ready |
| Forget `kubectl get events` | First command in any triage; second is `describe` |
| SSH to a node and reach for `docker ps` | `crictl ps`/`crictl logs` (containerd is the runtime) |
| Skip the etcd snapshot before mutating cluster state | RKE2: `rke2 etcd-snapshot save` is one command |
