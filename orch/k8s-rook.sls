{% set k8s = salt['pillar.get']('k8s') %}
k8s_rook-op:
  salt.state:
    - tgt: '{{ k8s }}' 
    - sls: /formulas/common/k8s-rook/configure