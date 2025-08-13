{% set k8s = salt['pillar.get']('k8s') %}


install_rook_cluster_{{ rook_version }}:
  salt.state:
    - tgt: {{ k8s }}
    - sls: /formulas/common/k8s-rook/cluster