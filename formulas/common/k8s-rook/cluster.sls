# Step 1: Ensure Helm is installed on the target node
include:
  - /formulas/common/helm/install

rook_ceph_cluster:
  rook.ceph_cluster_present:
    - name: rook-ceph
    - namespace: {{ pillar['res-k8s']['rook']['namespace'] }}
    - ceph_version: {{ pillar['res-k8s']['rook']['ceph_image'] }}
    - use_all_nodes: {{ pillar['res-k8s']['rook']['use_all_nodes'] }}
    - use_all_devices: {{ pillar['res-k8s']['rook']['use_all_devices'] }}
    - device_filter: {{ pillar['res-k8s']['rook']['device_filter'] }}
    - only_apply_osd_placement: true
    - metadata_device: nvme1n1
    - resources: {{ pillar['res-k8s']['rook']['resources'] }}
    - placement_pillar: res-k8s:rook:placement        # Clean!
    - network_provider: {{ pillar['res-k8s']['rook']['cluster']['network']['provider'] }}
    - public_network: {{ pillar['res-k8s']['rook']['cluster']['network']['addressRanges']['public'] }}
    - cluster_network: {{ pillar['res-k8s']['rook']['cluster']['network']['addressRanges']['cluster'] }}
    - dashboard_enabled: true
    - monitoring_enabled: false
    - toolbox_enabled: true

general_rbd_pool:
  rook.ceph_blockpool_present:
    - name: general
    - namespace: rook-ceph
    - failure_domain: host
    - replicated_size: 3

rook_ceph_block_storageclass:
  rook.storageclass_present:
    - name: rook-ceph-block
    - provisioner: rook-ceph.rbd.csi.ceph.com
    - parameters: {{ pillar['res-k8s']['rook']['rbd_pool']['class']['parameters'] }}
    - reclaim_policy: {{ pillar['res-k8s']['rook']['rbd_pool']['class']['reclaimPolicy'] }}
    - volume_binding_mode: {{ pillar['res-k8s']['rook']['rbd_pool']['class']['volumeBindingMode'] }}
    - allow_volume_expansion: {{ pillar['res-k8s']['rook']['rbd_pool']['class']['allowVolumeExpansion'] }}
