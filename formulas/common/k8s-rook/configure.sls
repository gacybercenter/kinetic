include:
  - /formulas/common/k8s-rook/install

# Add Rook Helm repo
add_rook_repo:
  k8s_helm.helm_repo_present:
    - repo_name: rook-release
    - repo_url: https://charts.rook.io/release

# Install Rook Operator
rook_operator:
  k8s_helm.helm_release_present:
    - release_name: rook-ceph
    - chart_name: rook-release/rook-ceph
    - namespace: {{ pillar['rook']['namespace'] }}
    - pillar_key: rook:operator
    - wait_timeout: 300
    - require:
      - k8s_helm: add_rook_repo
