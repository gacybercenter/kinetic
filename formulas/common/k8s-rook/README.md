# k8s-rook Formula

Modern Rook Ceph deployment using direct `CephCluster` CRD management instead of Helm for the cluster component.

## What We've Built

### New Modules

1. **`kinetic/_modules/kinetic-rook.py`** - Execution module with `ceph_cluster_present()`
2. **`kinetic/_states/rook.py`** - Salt state `rook.ceph_cluster_present`

### Key Features Implemented

- **Placement Configuration**: Full support for Rook's placement model (affinity, tolerations, nodeSelector)
- **`placement_pillar`**: Clean way to specify complex placement from pillar without cluttering formulas
- **Smart `node` → `all` mapping**: If pillar uses a `node` key, it's automatically mapped to `all` (Rook convention)
- **Multus Network Support**: Properly handles `namespace/nadname` format (e.g. `default/public`)
- **High-level API with sensible defaults**: Easy to use while allowing full `spec` override

## Pillar Structure

### Recommended Pillar

```yaml
rook:
  namespace: rook-ceph
  ceph_version: quay.io/ceph/ceph:v18.2.4

  # Resource defaults
  resources:
    limits:
      cpu: "2"
      memory: 4Gi
    requests:
      cpu: 500m
      memory: 1Gi

  # Network configuration
  network:
    provider: multus
    public: default/sfe-net      # namespace/nadname format
    cluster: default/sbe-net

# OSD devices
osd_mappings:
  storage:
    osd:
      - /dev/sdb
      - /dev/sdc

# Placement configuration (highly recommended)
rook:
  placement:
    node:                    # This gets mapped to 'all' automatically
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

## Formula Usage (`cluster.sls`)

```sls
{% set devices = salt['pillar.get']('osd_mappings:storage:osd', []) %}
{% set namespace = pillar['rook']['namespace'] %}

include:
  - /formulas/common/k8s

create_rook_namespace:
  k8s.namespace_present:
    - namespace: {{ namespace }}

rook_ceph_cluster:
  rook.ceph_cluster_present:
    - name: rook-ceph
    - namespace: {{ namespace }}
    - ceph_version: {{ pillar['rook']['ceph_version'] }}
    - devices: {{ devices }}
    - placement_pillar: rook:placement        # Clean!
    - network_provider: {{ pillar.get('rook:network:provider', 'host') }}
    - public_network: {{ pillar.get('rook:network:public') }}
    - cluster_network: {{ pillar.get('rook:network:cluster') }}
    - dashboard_enabled: true
    - monitoring_enabled: true
    - toolbox_enabled: true
    - require:
      - k8s: create_rook_namespace
```

## Alternative: Direct Placement

```sls
rook_ceph_cluster:
  rook.ceph_cluster_present:
    - name: rook-ceph
    - namespace: rook-ceph
    - placement:
        all:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: ceph-type
                  operator: In
                  values:
                  - storage
```

## Module Architecture

### `kinetic_rook.ceph_cluster_present()`

**Parameters:**
- `placement`: Direct placement dict
- `placement_pillar`: Pillar key (e.g. `rook:placement`)
- `network_provider`: `host` or `multus`
- `public_network`/`cluster_network`: For Multus, accepts `namespace/nadname` format
- Full `spec` override available

**Smart Behaviors:**
1. **`node` → `all` mapping**: If your pillar has a `node` key, it's automatically renamed to `all`
2. **Multus formatting**: If you provide just a NAD name like `public`, it becomes `default/public`
3. **Sensible defaults**: Good production defaults for tolerations and placement

### State Module

Provides `rook.ceph_cluster_present` state that wraps the execution module, consistent with other states in the project.

## Migration Notes

**From old Helm-based approach (`rook-ceph-cluster` chart):**

- Replace Helm release with `rook.ceph_cluster_present` state
- Move values from `rook-cluster.j2` into pillar under `rook:` and `rook:placement:`
- Use `placement_pillar: rook:placement` to keep formulas clean
- The Rook Operator is still installed via Helm (recommended approach)

## Related Documentation

- [Rook CephCluster CRD](https://rook.io/docs/rook/v1.20/CRDs/Cluster/ceph-cluster-crd/)
- [Placement Configuration](https://rook.io/docs/rook/v1.20/CRDs/Cluster/ceph-cluster-crd/#placement-example)
- [Multus Network Configuration](https://rook.io/docs/rook/v1.20/CRDs/Cluster/network-providers/#multus-configuration)

**Last updated**: July 2025
