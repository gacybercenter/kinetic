{% set k8s = salt['pillar.get']('k8s') %}

#Install typo3
k8s_typo3_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.typo3
