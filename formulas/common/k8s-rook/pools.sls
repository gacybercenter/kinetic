rook-csi-drivers:
  k8s_helm.helm_release_present:
    - release_name: ceph-csi-drivers
    - chart_name: ceph-csi-operator/ceph-csi-drivers
    - namespace: {{ pillar['res-k8s']['rook']['namespace'] }}
    - pillar_key: res-k8s:rook:csi_drivers
    - wait_timeout: 300

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
