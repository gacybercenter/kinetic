# Orchestration script to deploy OpenStack Helm Memcached.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_memcached:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-memcached