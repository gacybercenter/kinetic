include:
  - /formulas/common/k8s-rook/install

# Add Rook Helm repo
add_rook_repo:
  k8s_helm.helm_repo_present:
    - repo_name: rook-release
    - repo_url: https://charts.rook.io/release
add_csi_repo:
  k8s_helm.helm_repo_present:
    - repo_name: ceph-csi
    - repo_url: https://ceph.github.io/csi-charts

# Install Rook Operator
rook_operator:
  k8s_helm.helm_release_present:
    - release_name: rook-ceph
    - chart_name: rook-release/rook-ceph
    - namespace: {{ pillar['res-k8s']['rook']['namespace'] }}
    - pillar_key: rook:operator
    - wait_timeout: 300
    - require:
      - k8s_helm: add_rook_repo
rook-csi-operator:
  k8s_helm.helm_release_present:
    - release_name: rook-csi-rbd-drivers
    - chart_name: ceph-csi/ceph-csi-rbd
    - namespace: {{ pillar['res-k8s']['rook']['namespace'] }}
    - pillar_key: rook:csi_drivers
    - wait_timeout: 300
    - require:
      - k8s_helm: rook_operator
      - k8s_helm: add_csi_repo
