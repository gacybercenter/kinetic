include:
  - /formulas/olm/install

install_olm:
  k8s_helm.helm_release_present:
    - release_name: olm
    - chart_name: oci://ghcr.io/cloudtooling/helm-charts/olm
    - namespace: {{ pillar['olm_values']['namespace'] }}
    - wait_timeout: 300
    - wait_interval: 10
    - pillar_key: olm_values
    - version: 0.40.0
