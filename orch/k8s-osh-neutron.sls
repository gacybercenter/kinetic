# Orchestration script to deploy OpenStack Helm Neutron.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_neutron:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.neutron
