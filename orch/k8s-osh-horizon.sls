# Orchestration script to deploy OpenStack Helm Horizon.
# This script uses the k8s pillar value to target the minion where the
# installation should occur.
#
#   salt-run state.orchestrate orch.k8s-osh-horizon pillar='{"k8s": "master-rsc-0"}'

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_horizon:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.horizon
