# Orchestration script to deploy OpenStack Helm fluent.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_fluentbit:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-fluentbit

deploy_osh_fluent:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-fluentd
    - require:
      - salt: deploy_osh_fluentbit
