# Ensure the Jetstack Helm repository is available
ensure_jetstack_helm_repo:
  k8s_helm.helm_repo_present:
    - repo_name: jetstack
    - repo_url: https://charts.jetstack.io
    - update_cache: true

# Deploy cert-manager using the k8s_helm module
ensure_certmanager_release:
  k8s_helm.helm_release_present:
    - release_name: cert-manager
    - chart_name: jetstack/cert-manager
    - namespace: cert-manager
    - pillar_key: res-k8s:cert-manager
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s_helm: ensure_jetstack_helm_repo

ensure_trust_manager_release:
  k8s_helm.helm_release_present:
    - release_name: trust-manager
    - chart_name: oci://quay.io/jetstack/charts/trust-manager
    - namespace: cert-manager
    - pillar_key: res-k8s:trust-manager
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s_helm: ensure_certmanager_release
