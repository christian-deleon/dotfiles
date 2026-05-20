# Networking

The Kubernetes network model is deceptively simple: every pod gets a routable IP, every pod can reach every other pod, and `Service` gives you a stable name in front of a churning set of pod IPs. Everything above that — ingress, network policy, service mesh, DNS — is a layer building on those three facts. Most production-Kubernetes networking pain traces back to confusion about which of those layers a problem lives in.

## Services — the four kinds

| Type | What it gets you | Use for |
|---|---|---|
| `ClusterIP` (default) | Stable virtual IP + DNS name inside the cluster | Almost everything internal |
| `Headless` (`clusterIP: None`) | DNS only — A records per pod, no proxying | StatefulSets, peer-aware clients (Kafka, Cassandra) |
| `NodePort` | A port on every node, forwarded to the service | Almost never. Bare-metal LB workaround at best. |
| `LoadBalancer` | Provisions a cloud LB (or MetalLB / Cilium L2 announce / kube-vip on-prem) | External exposure when **not** going through Ingress |

Two anti-patterns:

- **`NodePort` in production.** It scrambles port numbers, requires nodes to be reachable, and offers nothing Ingress + a real LB doesn't.
- **`LoadBalancer` per microservice.** Each LB is real cloud cost. Use **one** ingress controller behind one LB; route by hostname/path.

### Service shape

```yaml
apiVersion: v1
kind: Service
metadata:
  name: checkout
  namespace: checkout
  labels:
    app.kubernetes.io/name: checkout
    app.kubernetes.io/instance: checkout-prod
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: checkout
    app.kubernetes.io/instance: checkout-prod    # immutable pair only
  ports:
    - name: http                                  # name every port
      port: 80
      targetPort: http                            # reference container port by name, not number
      protocol: TCP
  internalTrafficPolicy: Cluster                  # 'Local' to keep traffic on the same node
  ipFamilyPolicy: SingleStack
```

Rules:

- **Selector matches `name` + `instance` only.** Never select on `app.kubernetes.io/version` — you'll drop endpoints during a rollout.
- **Name every port.** `targetPort: http` is more robust than `targetPort: 8080`; the container can change its bind port without you re-finding every Service that referenced it.
- **`externalTrafficPolicy: Local`** on `LoadBalancer` Services preserves the client source IP but causes traffic to skip nodes without pods. Combined with `internalTrafficPolicy: Local`, you can pin all traffic to local pods — useful for daemon-style workloads, bad for general services.

### Headless Services for StatefulSets

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kafka
spec:
  clusterIP: None
  selector:
    app.kubernetes.io/name: kafka
  ports:
    - name: broker
      port: 9092
```

DNS becomes `<pod-name>.<service>.<ns>.svc.cluster.local` per pod. StatefulSets require a headless service named the same as the StatefulSet's `serviceName`.

### EndpointSlices

`Endpoints` (v1) is deprecated for new work. The cluster maintains `EndpointSlice` automatically — you almost never write one directly. The exception is **manually-managed external services** (pointing a Service at an off-cluster DB):

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: external-db-1
  labels:
    kubernetes.io/service-name: external-db
addressType: IPv4
ports:
  - name: pg
    port: 5432
endpoints:
  - addresses: ["10.0.10.5"]
    conditions: { ready: true }
```

Pair with a `Service` of `type: ClusterIP` and **no selector** — the slice is your endpoint source.

## Ingress with Traefik

Traefik is the default. New `Ingress` work prefers the **`IngressRoute` CRD** because it supports the parts of Traefik's feature surface (middlewares, TCP/UDP, weighted services) that the stock `Ingress` resource can't express. Stock `Ingress` is still acceptable when the upstream Helm chart only ships that shape — Traefik reconciles both.

### IngressRoute (preferred)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: checkout
  namespace: checkout
spec:
  entryPoints: [websecure]
  routes:
    - kind: Rule
      match: Host(`checkout.example.com`) && PathPrefix(`/api`)
      services:
        - name: checkout
          port: http
      middlewares:
        - name: rate-limit                       # references a Middleware CRD
        - name: ratelimit-headers                # always name your middlewares descriptively
  tls:
    secretName: checkout-tls                     # populated by cert-manager
```

Pair with a `Middleware` CRD for cross-cutting concerns:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: checkout
spec:
  rateLimit:
    average: 100
    burst: 200
```

### TLS via cert-manager

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: checkout-tls
  namespace: checkout
spec:
  secretName: checkout-tls
  dnsNames:
    - checkout.example.com
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

Issue **per-namespace certs**, not one mega-cert. cert-manager creates the `Secret` with `tls.crt`/`tls.key`; the `IngressRoute` references it by `tls.secretName`.

### Stock Ingress (when you have to)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: checkout
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.middlewares: checkout-rate-limit@kubernetescrd
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts: [checkout.example.com]
      secretName: checkout-tls
  rules:
    - host: checkout.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: checkout, port: { name: http } }
```

Annotations are how Traefik's advanced features bolt onto stock `Ingress`. `IngressRoute` exists precisely because annotations are a terrible API.

## Gateway API (future-compat)

Traefik (and Cilium, Istio, others) implement Gateway API. It's the replacement for `Ingress` in upstream Kubernetes, but adoption is mid-curve. **Default to Traefik's `IngressRoute` today** unless the project is explicitly Gateway-API-first.

When using Gateway API, the three core resources:

```yaml
# 1. GatewayClass — installed once per cluster, points at a controller
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata: { name: traefik }
spec: { controllerName: traefik.io/gateway-controller }
---
# 2. Gateway — listener config (TLS, ports, hosts)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: edge, namespace: traefik }
spec:
  gatewayClassName: traefik
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "*.example.com"
      tls:
        mode: Terminate
        certificateRefs: [{ name: wildcard-tls }]
      allowedRoutes: { namespaces: { from: All } }
---
# 3. HTTPRoute — per-namespace routing rules, can reference an upstream Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: checkout, namespace: checkout }
spec:
  parentRefs: [{ name: edge, namespace: traefik }]
  hostnames: [checkout.example.com]
  rules:
    - matches: [{ path: { type: PathPrefix, value: /api } }]
      backendRefs: [{ name: checkout, port: 80 }]
```

The win over `Ingress`: per-namespace `HTTPRoute` ownership without annotation soup, real RBAC boundaries between platform team (Gateway) and app teams (Route).

## NetworkPolicy — default-deny, then allow

The cluster's default is **allow all pod-to-pod traffic**. That is wrong for production. Establish a default-deny posture per namespace, then explicitly allow what's needed:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: checkout
spec:
  podSelector: {}                                # matches every pod
  policyTypes: [Ingress, Egress]
  # no ingress or egress rules => deny everything
```

Then layer allow rules:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-traefik-to-checkout
  namespace: checkout
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: checkout
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: traefik
          podSelector:
            matchLabels:
              app.kubernetes.io/name: traefik
      ports:
        - protocol: TCP
          port: 8080
```

```yaml
# Egress: allow DNS to kube-system, allow Postgres to the db namespace, deny rest
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-egress-baseline, namespace: checkout }
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: postgres
      ports:
        - protocol: TCP
          port: 5432
```

Rules:

- **Default-deny first, then allow.** A namespace without any NetworkPolicy is open by default; adding one allow-rule does **not** deny anything else by itself.
- **CIDR allow-rules to `0.0.0.0/0` defeat the point.** Allow specific destinations.
- **Egress to external hostnames is hard in vanilla NetworkPolicy** — it works on IPs, not DNS. For "allow this pod to call api.stripe.com" use Cilium's L7 `CiliumNetworkPolicy` or sidecar a proxy (Envoy, Istio).
- **Enforcement requires a CNI that implements it.** Cilium does. Calico does. Bare Flannel does not. RKE2's default Canal does (Calico + Flannel).

### Cilium L7 NetworkPolicy

For L7 controls (HTTP path/method, gRPC service/method, Kafka topic), use `CiliumNetworkPolicy`:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: { name: allow-checkout-get-orders, namespace: checkout }
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: checkout
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: frontend
      toPorts:
        - ports: [{ port: "8080", protocol: TCP }]
          rules:
            http:
              - method: GET
                path: "/orders.*"
```

## DNS — what's actually happening

In-cluster DNS (CoreDNS by default; CoreDNS or NodeLocal DNSCache in production) resolves:

| Query | Resolves to |
|---|---|
| `<svc>` (from inside the same namespace) | The Service ClusterIP |
| `<svc>.<ns>` | Same |
| `<svc>.<ns>.svc.cluster.local` | Same (the fully-qualified form) |
| `<pod-ip-with-dashes>.<ns>.pod.cluster.local` | The pod (rarely used) |
| `<pod-name>.<headless-svc>.<ns>.svc.cluster.local` | Specific pod IP (StatefulSet pattern) |

`ndots: 5` is the kubelet default. It causes most lookups to be **searched** through `<ns>.svc.cluster.local`, `svc.cluster.local`, `cluster.local`, and the node search list before resolving externally. For latency-sensitive workloads, override:

```yaml
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "2"
  dnsPolicy: ClusterFirst
```

For very high-DNS-QPS workloads (anything making per-request external HTTP calls), enable **NodeLocal DNSCache** at the cluster level. Defer cluster-level tuning to [clusters.md](clusters.md).

## Dual-stack and IPv6

```yaml
spec:
  ipFamilyPolicy: PreferDualStack             # SingleStack | PreferDualStack | RequireDualStack
  ipFamilies: [IPv4, IPv6]
```

Cluster must be installed dual-stack (`--service-cluster-ip-range=<v4>,<v6>`). Defer cluster-install specifics to [clusters.md](clusters.md).

## Service mesh — when (rarely)

Don't add one by default. Reach for one only when you need one of:

- **mTLS everywhere** with automatic cert rotation per pod identity, enforced at the dataplane.
- **L7 traffic shifting** (canary by header, fault injection, circuit breaking) you can't get from Traefik routing.
- **Multi-cluster service discovery** spanning more than one Kubernetes cluster.

When you do — prefer **Istio ambient mode** (no sidecars; ztunnel + per-namespace waypoint proxy) or **Linkerd**. Both are far cheaper than classic sidecar Istio. Cilium service mesh is a strong option when you're already on Cilium.

A mesh is a permanent operational commitment. Treat the decision accordingly.

## Don't / Do

| Don't | Do |
|---|---|
| `NodePort` in production | `LoadBalancer` behind an ingress controller |
| `LoadBalancer` per service | One ingress controller behind one LB, routed by host/path |
| Select on `app.kubernetes.io/version` | Select on `name` + `instance` only |
| `targetPort: 8080` (port number) | `targetPort: http` (port name) |
| Stock `Ingress` + huge annotation block | Traefik `IngressRoute` CRD |
| Wildcard cert for everything | Per-namespace `Certificate` via cert-manager |
| Forget the default-deny `NetworkPolicy` | Default-deny per namespace, then explicit allow |
| Egress-allow to `0.0.0.0/0` | Specific destinations; Cilium L7 for FQDN allowlist |
| `dnsPolicy: Default` (uses node DNS, breaks in-cluster) | `ClusterFirst` (default; CoreDNS in front) |
| Sidecar mesh by reflex | Add a mesh only when you can name what it gives you |
| Edit `kube-proxy` settings by hand | Configure via CNI install values (Cilium replaces kube-proxy entirely) |
| Hardcode service IPs anywhere | DNS name; IPs change on Service recreate |
| `services.<ns>.svc.cluster.local` (typo, common) | `<svc>.<ns>.svc.cluster.local` |
