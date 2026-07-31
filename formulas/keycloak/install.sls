include:
  - /formulas/common/helm
  - /formulas/common/k8s-cnpg

keycloak_install:
  k8s_helm.helm_release_present:
    - release_name: keycloak
    - chart_name: {{ pillar['res-k8s']['keycloak']['chart_name']
    - namespace: keycloak
    - pillar_key: helm:myapp:values
