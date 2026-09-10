# Orchestration script to deploy OpenStack Helm Cinder.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_cinder:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.cinder
