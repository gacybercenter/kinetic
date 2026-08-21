# Orchestration script to deploy OpenStack Helm repository and plugin on a targeted Kubernetes minion.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_helm_repos:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-helm-repos