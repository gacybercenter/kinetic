# Add or update the CloudNativePG Helm repository using helm_repo_present
add_cnpg_repo:
  k8s_helm.helm_repo_present:
    - repo_name: cloudnative-pg
    - repo_url: https://cloudnative-pg.github.io/charts

# Install or upgrade CloudNativePG operator using Helm via k8s_helm state
install_cnpg_operator:
  k8s_helm.helm_release_present:
    - release_name: cloudnative-pg
    - chart_name: cloudnative-pg/cloudnative-pg
    - namespace: {{ pillar.get('cnpg_namespace', 'cnpg-system') }}
    - pillar_key: res-k8s:cnpg:helm_values
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s_helm: add_cnpg_repo