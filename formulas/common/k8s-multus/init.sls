include:
  - /formulas/common/k8s-multus/install

# Ensure the Multus Helm repository is available
ensure_multus_helm_repo:
  k8s_helm.helm_repo_present:
    - repo_name: k8snetworkplumbingwg
    - repo_url: https://charts.bitnami.com/bitnami
    - update_cache: true

# Deploy Multus using the new k8s_helm state with pillar_key
ensure_multus_release:
  k8s_helm.helm_release_present:
    - release_name: multus
    - chart_name: bitnami/multus-cni
    - namespace: kube-system
    - pillar_key: res-k8s:multus:values
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s_helm: ensure_multus_helm_repo
