{% set k8s = salt['pillar.get']('k8s') %}

k8s_kps_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.k8s-prom-stack.install
