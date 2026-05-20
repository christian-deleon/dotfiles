# Storage

Kubernetes storage is three concepts:

| Concept | What it is |
|---|---|
| `StorageClass` | A template — "this is how to provision a volume on this cluster" |
| `PersistentVolumeClaim` (PVC) | A *request* for storage — size, mode, class |
| `PersistentVolume` (PV) | The actual provisioned volume — usually created dynamically from a PVC, almost never written by hand |

The model is **dynamic provisioning**: a workload writes a PVC, the corresponding CSI driver sees it, creates the underlying disk/volume, and binds a PV. You should rarely create PVs directly. If you find yourself writing one, you're either importing an existing volume or working without a CSI driver — both are unusual.

## StorageClass — the cluster-level decision

Every cluster needs at least one `StorageClass`, ideally with one of them marked `default`. Look at what's already installed before defining new ones:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"        # only one default per cluster
provisioner: ebs.csi.aws.com                                   # CSI driver name; varies per cluster
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
reclaimPolicy: Retain                                          # see below
volumeBindingMode: WaitForFirstConsumer                        # see below
allowVolumeExpansion: true
```

### Two settings that get every cluster wrong

**`volumeBindingMode: WaitForFirstConsumer`** — bind the PV *after* a pod is scheduled, so the volume is provisioned in the **right zone** for the pod. The default (`Immediate`) creates the volume immediately in *some* zone, and now your pod may be unschedulable because it can't be placed in the volume's zone. `WaitForFirstConsumer` is the right default for any topology-constrained volume (every cloud block volume, basically). The exception is shared filesystems (EFS, FSx, NFS) that aren't zone-constrained.

**`reclaimPolicy: Retain`** vs `Delete` — what happens when the PVC is deleted:

- `Delete` (default for dynamically-provisioned PVs in most clusters): the underlying volume is **destroyed**. Fine for cattle workloads.
- `Retain`: the underlying volume persists, the PV moves to `Released`. Recover by editing the PV to clear `claimRef` and rebinding.

For anything stateful — databases, queues, anything you'd cry over losing — make the class `Retain`. The cost is occasional orphaned PVs that need cleanup; the alternative is data loss on a stray `kubectl delete pvc`.

### Common provisioners

| Backend | Provisioner |
|---|---|
| AWS EBS | `ebs.csi.aws.com` |
| AWS EFS (shared filesystem, multi-AZ ReadWriteMany) | `efs.csi.aws.com` |
| GCP PD | `pd.csi.storage.gke.io` |
| Azure Disk | `disk.csi.azure.com` |
| Longhorn (on-prem, RKE2 default companion) | `driver.longhorn.io` |
| Rook-Ceph | `rook-ceph.cephfs.csi.ceph.com` (RWX) / `rook-ceph.rbd.csi.ceph.com` (RWO) |
| NFS (external) | `nfs.csi.k8s.io` |
| `local-path` (K3s/k3d default) | `rancher.io/local-path` |

K3s and k3d ship with `local-path` as default — fine for dev, **not** for production. It binds the volume to a node-local hostpath; if the node dies, the data dies. For single-node K3s production, accept that constraint deliberately or use Longhorn.

## PVC — the request side

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: checkout
spec:
  accessModes: [ReadWriteOnce]                                 # see access modes table
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 20Gi
```

For ephemeral pod-scoped storage (no persistence across pod restarts), use a **generic ephemeral volume** in the PodSpec instead of a separately-managed PVC:

```yaml
spec:
  containers:
    - name: app
      volumeMounts:
        - { name: scratch, mountPath: /scratch }
  volumes:
    - name: scratch
      ephemeral:
        volumeClaimTemplate:
          spec:
            accessModes: [ReadWriteOnce]
            storageClassName: fast-ssd
            resources:
              requests: { storage: 5Gi }
```

The PVC is created with the pod and deleted with it. Good for scratch space larger than `emptyDir` should be.

## Access modes — what each does

| Mode | Meaning | Common for |
|---|---|---|
| `ReadWriteOnce` (RWO) | Mountable read-write by a single **node** at a time | Block volumes; default — every database |
| `ReadWriteOncePod` (RWOP) | Mountable by a single **pod** at a time | Strong-singleton workloads (1.27+) |
| `ReadOnlyMany` (ROX) | Read-only by many nodes | Rare — shared read assets |
| `ReadWriteMany` (RWX) | Read-write by many nodes | Shared filesystems — NFS, EFS, CephFS, Longhorn-CSI-RWX |

`ReadWriteOnce` is **per-node, not per-pod** — two pods on the same node can mount the same RWO volume. If you actually need single-pod, use `ReadWriteOncePod` (1.27+).

RWX is expensive and easy to misuse. If you want RWX because "multiple replicas need to write to the same place," reconsider — that's usually a sign you need an object store, not a filesystem.

## StatefulSet volumes — `volumeClaimTemplates`

The canonical pattern for "I need N replicas, each with its own persistent storage":

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: kafka, namespace: kafka }
spec:
  serviceName: kafka                                            # headless Service name
  replicas: 3
  selector:
    matchLabels: { app.kubernetes.io/name: kafka }
  template:
    metadata:
      labels: { app.kubernetes.io/name: kafka }
    spec:
      containers:
        - name: kafka
          image: ghcr.io/example/kafka@sha256:<digest>
          volumeMounts:
            - { name: data, mountPath: /var/lib/kafka }
  volumeClaimTemplates:
    - metadata: { name: data }                                  # PVCs created as <name>-<pod>-<ordinal>
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: fast-ssd
        resources: { requests: { storage: 100Gi } }
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain                                          # never reap on StatefulSet delete
    whenScaled: Retain                                           # don't reap when scaling down
```

PVCs are created as `data-kafka-0`, `data-kafka-1`, `data-kafka-2`. They are **not** auto-deleted when the StatefulSet is deleted (with `Retain`) — by design.

`persistentVolumeClaimRetentionPolicy` defaults to `Retain` for both, which is correct. Set `whenScaled: Delete` only if you've decided scaling down should reclaim disk (almost always wrong for stateful systems).

## Resizing a volume

`allowVolumeExpansion: true` on the StorageClass + edit the PVC's `resources.requests.storage`:

```bash
kubectl patch pvc data-kafka-0 -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

For most CSI drivers this is online (no pod restart). For some it requires a pod restart for the filesystem to grow. Check the CSI driver docs.

**Shrinking is not supported.** Create a new larger volume and migrate.

## Volume snapshots

`VolumeSnapshot` is the cluster API for "snapshot this PVC":

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata: { name: ebs-snapshots }
driver: ebs.csi.aws.com
deletionPolicy: Retain
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: { name: kafka-0-pre-upgrade, namespace: kafka }
spec:
  volumeSnapshotClassName: ebs-snapshots
  source:
    persistentVolumeClaimName: data-kafka-0
```

Restore by creating a new PVC with `dataSource:` referencing the snapshot:

```yaml
spec:
  dataSource:
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: kafka-0-pre-upgrade
```

Use Velero for backup as a higher-level abstraction — it handles snapshots + namespace manifests + sequencing. Raw `VolumeSnapshot` is for in-cluster orchestration (operator-driven backups).

## Topology and zone awareness

Cloud block storage is **zonal** — an EBS volume in `us-east-1a` can never attach to a pod in `us-east-1b`. Two implications:

- `volumeBindingMode: WaitForFirstConsumer` is non-negotiable for cloud block storage.
- StatefulSet replicas spread across AZs **lose** their PVs when the AZ fails. There's no "move the PV." For multi-AZ HA in a single StatefulSet you need application-level replication (Kafka, Postgres streaming replication, etc.), not storage-level replication.

Cross-AZ replicated storage (Longhorn, Rook-Ceph with multi-AZ topology, Portworx) trades cost and complexity for the ability to fail over storage. Use it only when application-level replication isn't feasible.

## Local volumes — when zero remote storage is acceptable

`hostPath` is the wrong answer in production. The right answer for "this needs to be on the node's disk" is:

- **`local` PersistentVolume** (statically provisioned) — node-affinity-pinned, real volume lifecycle. Used for high-IO workloads that can tolerate node-loss == data-loss.
- **K3s/k3d `local-path` provisioner** — dev only.
- **Longhorn** (on-prem) — replicated across nodes; data survives single-node loss.

`emptyDir` is for ephemeral pod-scoped scratch and exits with the pod. `emptyDir.medium: Memory` is a tmpfs backed by RAM — counted against the pod's memory limit. Use it for scratch you actually want fast.

## CSI add-ons worth knowing

| Driver | Why |
|---|---|
| **Longhorn** | On-prem replicated block storage. RKE2 + Longhorn is the default on-prem stack. |
| **Rook-Ceph** | Heavier-weight on-prem distributed storage (block + filesystem + object). Worth it for scale. |
| **CSI Secrets Store** | Mount secrets from Vault/AWS Secrets Manager directly as files, no `Secret` object on the cluster. See [config-secrets.md](config-secrets.md). |
| **CSI snapshotter** | Snapshot CRDs — install separately if your cluster doesn't have it. |
| **CSI image populator** | Populate a PVC's initial contents from an OCI image. Useful for ML model preloading. |

## Don't / Do

| Don't | Do |
|---|---|
| `hostPath` in production | `local` PV, Longhorn, or proper CSI driver |
| Define a StorageClass without `volumeBindingMode: WaitForFirstConsumer` (for topology-constrained drivers) | Set it explicitly |
| `reclaimPolicy: Delete` for stateful data | `Retain` for production data classes |
| Static PVs handwritten in YAML | Dynamic provisioning via StorageClass + PVC |
| StatefulSet without `volumeClaimTemplates` | Use the template; one PVC per replica |
| `persistentVolumeClaimRetentionPolicy: { whenDeleted: Delete }` on stateful workloads | `Retain` for both fields |
| `ReadWriteMany` because "it's easier" | Reconsider; usually you want object storage or a real database |
| Resize by deleting and recreating | `allowVolumeExpansion: true` + patch the PVC |
| Shrink a PVC | Provision a new one, migrate data, swap |
| `emptyDir.medium: Memory` without lowering memory limits | Memory tmpfs counts against pod limit — size it |
| Forget to backup PVs (snapshots alone aren't backups) | Velero with snapshot integration, periodic restore tests |
| `local-path` on K3s in production without accepting node-loss == data-loss | Longhorn on K3s for non-trivial production |
| Snapshot without a `VolumeSnapshotClass` installed | Install the CSI snapshotter; verify it's present before relying on snapshots |
