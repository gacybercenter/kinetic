{% set k8s = salt['pillar.get']('k8s') %}

setup_rbd_pool:
  salt.state:
    - tgt: {{ k8s }}
    - sls: /formulas/common/k8s-rook/pools
