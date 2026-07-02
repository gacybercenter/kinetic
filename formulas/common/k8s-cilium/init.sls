include:
  - /formulas/common/k8s-cilium/install

# Ensure the Cilium Helm repository is available
ensure_cilium_helm_repo:
  k8s_helm.helm_repo_present:
    - repo_name: cilium
    - repo_url: https://helm.cilium.io/
    - update_cache: true

# Deploy Cilium using the new k8s_helm state with pillar_key (no temporary file needed)
ensure_cilium_release:
  k8s_helm.helm_release_present:
    - release_name: cilium
    - chart_name: cilium/cilium
    - namespace: kube-system
    - pillar_key: res-k8s:cilium:values
    - wait_timeout: 600
    - wait_interval: 15
    - require:
      - k8s_helm: ensure_cilium_helm_repo
