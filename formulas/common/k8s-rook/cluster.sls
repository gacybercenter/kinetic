# Step 1: Ensure Helm is installed on the target node
include:
  - /formulas/common/helm/install

rook_ceph_cluster:
  rook.ceph_cluster_present:
    - name: rook-ceph
    - namespace: {{ pillar['res-k8s']['rook']['namespace'] }}
    - ceph_version: {{ pillar['res-k8s']['rook']['ceph_image'] }}
    - devices: {{ pillar['res-k8s']['rook']['storage']['osd']  }}
    - placement_pillar: rook:placement        # Clean!
    - network_provider: {{ pillar['res-k8s']['rook']['cluster']['network']['provider'] }}
    - public_network: {{ pillar['res-k8s']['rook']['cluster']['network']['public'] }}
    - cluster_network: {{ pillar['res-k8s']['rook']['cluster']['network']['cluster'] }}
    - dashboard_enabled: true
    - monitoring_enabled: true
    - toolbox_enabled: true
    - require:
      - k8s: create_rook_namespace
