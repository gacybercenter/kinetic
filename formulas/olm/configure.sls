include:
  - formulas/olm/install

olm_chart_install:
  helm.release_present:
    - name: olm
    - chart: oci://ghcr.io/cloudtooling/helm-charts/olm
    - version: 0.40.0
    - namespace: {{ pillar['olm_values']['namespace'] }}
    - values: {{ pillar['olm_values'] | yaml }}
    - require:
      - sls: formulas/olm/install
