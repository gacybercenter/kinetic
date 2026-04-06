# Orchestration script to deploy GitLab Runner on a targeted Kubernetes minion.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_gitlab_runner:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.k8s-gitlab-runner