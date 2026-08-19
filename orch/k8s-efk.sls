{% set k8s = salt['pillar.get']('k8s') %}


deploy_elk:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.common.k8s-efk
