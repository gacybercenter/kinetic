include:
  - /formulas/common/helm
  - /formluas/common/k8s-cnpg

# Add or update the Adfinis Helm repository for Keycloak operator
add_adfinis_repo:
  k8s_helm.helm_repo_present:
    - repo_name: adfinis
    - repo_url: https://adfinis.github.io/helm-charts/
    - update: true
# Install or upgrade Keycloak operator using Helm via k8s_helm state with values from pillar
install_keycloak_operator:
  k8s_helm.helm_release_present:
    - release_name: keycloak-operator
    - chart_name: adfinis/keycloak-operator
    - namespace: {{ pillar.get('keycloak_namespace', 'keycloak') }}
    - values_dict: {{ pillar.get('kc-op:operator', {}) }}
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s_helm: add_adfinis_repo

