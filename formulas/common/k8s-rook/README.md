# k8s-rook Formula

This formula installs and configures **Rook Ceph** using direct `CephCluster` CRD management instead of the Helm `rook-ceph-cluster` chart. It provides a clean, pillar-driven approach with high-level parameters.

## Current Features

The `rook.ceph_cluster_present` state supports:

- **Storage Configuration**: `use_all_nodes`, `use_all_devices`, `device_filter`, `metadata_device`, `only_apply_osd_placement`
- **Resource Configuration**: Per-daemon limits/requests via `resources` or `resources_pillar`
- **Network Configuration**: Both `host` (with `addressRanges`) and `multus` (with `namespace/nadname` format)
- **Placement Configuration**: Full Rook placement support via `placement` or `placement_pillar`
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

## Formula Usage (`cluster.sls`)

```sls
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
    - use_all_nodes: {{ pillar.get('res-k8s:rook:use_all_nodes', True) }}
    - use_all_devices: {{ pillar.get('res-k8s:rook:use_all_devices', False) }}
    - device_filter: {{ pillar.get('res-k8s:rook:device_filter') }}
    - metadata_device: {{ pillar.get('res-k8s:rook:metadata_device') }}
    - only_apply_osd_placement: {{ pillar.get('res-k8s:rook:only_apply_osd_placement', False) }}
    - resources_pillar: res-k8s:rook:resources
    - placement_pillar: rook:placement
    - network_provider: {{ pillar.get('res-k8s:rook:network:provider', 'host') }}
    - public_network: {{ pillar.get('res-k8s:rook:network:public') }}
    - cluster_network: {{ pillar.get('res-k8s:rook:network:cluster') }}
    - dashboard_enabled: true
    - monitoring_enabled: true
    - toolbox_enabled: true
    - require:
      - k8s: create_rook_namespace
```

## Module Architecture

### `kinetic_rook.ceph_cluster_present()`

**Key Parameters:**
- Storage: `use_all_nodes`, `use_all_devices`, `device_filter`, `metadata_device`, `only_apply_osd_placement`
- Resources: `resources` or `resources_pillar` (per-daemon limits/requests)
- Placement: `placement` or `placement_pillar`
- Network: `network_provider`, `public_network`, `cluster_network`

**Smart Behaviors:**
1. **`node` → `all` mapping**: Pillar component `node` is automatically renamed to `all`
2. **Host networking**: Uses `addressRanges.public` and `addressRanges.cluster` structure as requested
3. **Multus formatting**: Converts simple NAD names to `namespace/nadname` format
4. **Sensible defaults**: Production-ready defaults for placement and storage

## Migration Notes

- Replaced the complex `osd_mappings` nested structure with simple parameters
- Moved from Jinja2 templates to pillar-driven configuration
- Much cleaner SLS files using `placement_pillar` and `resources_pillar`
- The Rook Operator is still installed via Helm (recommended approach)

## Related Documentation

- [Rook CephCluster CRD](https://rook.io/docs/rook/v1.20/CRDs/Cluster/ceph-cluster-crd/)
- [Placement Configuration](https://rook.io/docs/rook/v1.20/CRDs/Cluster/ceph-cluster-crd/#placement-example)
- [Network Configuration](https://rook.io/docs/rook/v1.20/CRDs/Cluster/network-providers/)
- [Resource Configuration](https://rook.io/docs/rook/v1.20/CRDs/Cluster/ceph-cluster-crd/#cluster-wide-resources-configuration-settings)

**Last updated**: July 2025
