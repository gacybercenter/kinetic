# k8s-rook Formula

This formula installs and configures **Rook Ceph** using direct `CephCluster` CRD management instead of the Helm `rook-ceph-cluster` chart. It provides a clean, pillar-driven approach with high-level parameters.

## Orchestration Architecture

The deployment is now split into two phases for better reliability:

### 1. `orch/k8s-rook-cluster.sls`
- Node labeling and tainting
- CephCluster installation via `rook.ceph_cluster_present`
- **Health check**: Runs `kubectl rook-ceph ceph status` and waits for `HEALTH_OK`
- Only proceeds to pool creation once Ceph is healthy

### 2. `orch/k8s-rook-pools.sls`
- Creates CephBlockPool(s)
- Creates corresponding StorageClass(es)
- Only runs after the health check passes
# k8s-rook Formula

This formula installs and configures **Rook Ceph** using direct `CephCluster` CRD management. The orchestration has been split into two phases for better reliability and to ensure pools are only created after Ceph reports `HEALTH_OK`.

## Orchestration Architecture

The deployment is now split into two orchestration files:

### 1. `orch/k8s-rook-cluster.sls`
- Assigns node labels and taints (`rook-node`, `rook-osd-node`)
- Installs the Rook Operator and CephCluster via `rook.ceph_cluster_present`
- **Health Check**: Runs `kubectl rook-ceph ceph status` and waits for `HEALTH_OK`
- Uses retry logic (30 attempts, 10s intervals, 5 minutes total)
- Only proceeds to pool creation once Ceph is healthy

### 2. `orch/k8s-rook-pools.sls`
- Creates CephBlockPool(s) via `rook.ceph_blockpool_present`
- Creates corresponding StorageClass(es) via `rook.storageclass_present`
- Only runs after the health check in the cluster orchestration passes

Run with:
```bash
salt-run state.orch k8s-rook-cluster
```

## Current Features

The `rook.ceph_cluster_present` state supports:

- **Storage Configuration**: `use_all_nodes`, `use_all_devices`, `device_filter`, `metadata_device`, `only_apply_osd_placement`
- **Resource Configuration**: Per-daemon limits/requests via `resources` or `resources_pillar`
- **Network Configuration**: Both `host` (with `addressRanges`) and `multus` (with `namespace/nadname` format)
- **Placement Configuration**: Full Rook placement support via `placement` or `placement_pillar`
- **CephBlockPool & StorageClass**: Dedicated states for RBD pools and StorageClasses
- **Smart Behaviors**: `node`→`all` mapping, automatic Multus formatting, sensible defaults

## Pillar Structure

### Complete Example (`res-k8s:rook`)

```yaml
res-k8s:
  rook:
    namespace: rook-ceph
    ceph_version: quay.io/ceph/ceph:v18.2.4

    # Storage configuration
    use_all_nodes: true
    use_all_devices: false
    device_filter: "^sd."                    # or "nvme.*"
    metadata_device: "md0"                   # dedicated metadata device
    only_apply_osd_placement: false

    # Resource limits per daemon (mon, mgr, osd, etc.)
    resources:
      mon:
        limits:
          cpu: "2"
          memory: "2Gi"
        requests:
          cpu: "1"
          memory: "512Mi"
      mgr:
        limits:
          cpu: "2"
          memory: "4Gi"
        requests:
          cpu: "500m"
          memory: "1Gi"
      osd:
        limits:
          cpu: "4"
          memory: "8Gi"
        requests:
          cpu: "2"
          memory: "4Gi"

    # Network configuration
    network:
      provider: host
      public:
        - "10.150.2.0/24"
        - "10.150.3.0/24"
      cluster:
        - "10.150.4.0/24"

    # RBD Pool and StorageClass configuration
    rbd_pool:
      pool:
        name: general
        spec:
          failureDomain: host
          replicated:
            size: 3
      class:
        name: rook-ceph-block
        provisioner: rook-ceph.rbd.csi.ceph.com
        parameters:
          pool: general
          imageFormat: "2"
          imageFeatures: layering,fast-diff,object-map,deep-flatten,exclusive-lock
          csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
          csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
          csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
          csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
          csi.storage.k8s.io/controller-publish-secret-name: rook-csi-rbd-provisioner
          csi.storage.k8s.io/controller-publish-secret-namespace: rook-ceph
          csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
          csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
          csi.storage.k8s.io/node-publish-secret-name: rook-csi-rbd-node
          csi.storage.k8s.io/node-publish-secret-namespace: rook-ceph
          csi.storage.k8s.io/fstype: ext4
          clusterID: rook-ceph
        reclaimPolicy: Delete
        volumeBindingMode: Immediate
        allowVolumeExpansion: true

# Placement configuration (highly recommended)
rook:
  placement:
    node:                                 # Gets mapped to 'all' automatically
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: ceph-type
              operator: In
              values:
              - storage
      tolerations:
      - key: node-role.kubernetes.io/rook-node
        operator: Exists
        effect: NoSchedule

    mgr:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: ceph-type
              operator: In
              values:
              - mon

    osd:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: ceph-type
              operator: In
              values:
              - osd
```

## Orchestration Usage

### Full Deployment

```bash
salt-run state.orch k8s-rook-cluster
```

This runs:
1. Node labeling and tainting
2. CephCluster installation
3. Health check (`kubectl rook-ceph ceph status`)
4. Pool and StorageClass creation (only if HEALTH_OK)

### Pools Only (after cluster is healthy)

```bash
salt-run state.orch k8s-rook-pools
```

## Module Architecture

### Core States

- `rook.ceph_cluster_present()` - Creates and manages `CephCluster`
- `rook.ceph_blockpool_present()` - Creates `CephBlockPool` CRs
- `rook.storageclass_present()` - Creates Kubernetes StorageClasses with proper CSI parameters including `clusterID`

### Smart Behaviors

1. **`node` → `all` mapping** in placement configuration
2. **Automatic Multus formatting** (`public` becomes `default/public`)
3. **Health verification** before pool creation using your kubectl plugin
4. **Pillar-driven configuration** for all components

## Key Files

- `formulas/common/k8s-rook/cluster.sls` - CephCluster installation
- `formulas/common/k8s-rook/pools.sls` - Pool and StorageClass creation
- `orch/k8s-rook-cluster.sls` - Main orchestration with health check
- `orch/k8s-rook-pools.sls` - Pool orchestration (run after HEALTH_OK)
- `_modules/kinetic-rook.py` - Execution module with all Ceph states
- `_states/rook.py` - State wrappers

## Related Documentation

- [Rook CephCluster CRD](https://rook.io/docs/rook/v1.20/CRDs/Cluster/ceph-cluster-crd/)
- [Rook Storage Configuration](https://rook.io/docs/rook/v1.20/CRDs/Cluster/ceph-cluster-crd/#storage-configuration)
- [Rook Placement Configuration](https://rook.io/docs/rook/v1.20/CRDs/Cluster/ceph-cluster-crd/#placement-example)
- [Rook Network Providers](https://rook.io/docs/rook/v1.20/CRDs/Cluster/network-providers/)

**Last updated**: July 2025
