# Create KMS ConfigMap for Ceph CSI (Vault integration)
rook_csi_kms_configmap:
  k8s.configmap_present:
    - name: rook-ceph-csi-kms-config
    - configmap_name: csi-kms-connection-details
    - namespace: rook-ceph
    - data:
        vault-kms: |-
          {
            "encryptionKMSType": "vault",
            "vaultAddress": "https://vault.rook-ceph.svc:8200",
            "vaultAuthPath": "/v1/auth/kubernetes/login",
            "vaultRole": "rook-ceph-csi",
            "vaultBackend": "kv-v2",
            "vaultBackendPath": "rook",
            "vaultPassphrasePath": "ceph-csi/",
            "vaultDestroyKeys": "true",
            "vaultCAVerify": "false"
          }
    - labels:
        app: rook-ceph
        component: csi-kms

rook-csi-drivers:
  k8s_helm.helm_release_present:
    - release_name: ceph-csi-drivers
    - chart_name: ceph-csi-operator/ceph-csi-drivers
    - namespace: {{ pillar['res-k8s']['rook']['namespace'] }}
    - pillar_key: res-k8s:rook:csi_drivers
    - wait_timeout: 300
    - require:
      - k8s: rook_csi_kms_configmap
{% set pool = pillar['res-k8s']['rook']['rbd_pool'] %}

general_rbd_pool:
  rook.ceph_blockpool_present:
    - name: {{ pool['pool']['name'] }}
    - namespace: rook-ceph
    - failure_domain: host
    - replicated_size: 3
    - require:
      - k8s_helm: rook-csi-drivers

rook_ceph_block_storageclass:
  rook.storageclass_present:
    - name: {{ pool['class']['name'] }}
    - provisioner: {{ pool['class']['provisioner'] }}
    - parameters: {{ pool['class']['parameters'] }}
    - reclaim_policy: {{ pool['class']['reclaimPolicy'] }}
    - volume_binding_mode: {{ pool['class']['volumeBindingMode'] }}
    - allow_volume_expansion: {{ pool['class']['allowVolumeExpansion'] }}
    - require:
      - rook: general_rbd_pool

{% set pool = pillar['res-k8s']['rook']['encrypted_rbd_pool'] %}
general_rbd_encrypted_pool:
  rook.ceph_blockpool_present:
    - name: {{ pool['pool']['name'] }}
    - namespace: rook-ceph
    - failure_domain: host
    - replicated_size: 3
    - require:
      - k8s_helm: rook-csi-drivers

rook_ceph_block_encrypted_storageclass:
  rook.storageclass_present:
    - name: {{ pool['class']['name'] }}
    - provisioner: {{ pool['class']['provisioner'] }}
    - parameters: {{ pool['class']['parameters'] }}
    - reclaim_policy: {{ pool['class']['reclaimPolicy'] }}
    - volume_binding_mode: {{ pool['class']['volumeBindingMode'] }}
    - allow_volume_expansion: {{ pool['class']['allowVolumeExpansion'] }}
    - require:
      - rook: general_rbd_encrypted_pool
