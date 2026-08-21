# Orchestration script to deploy NGINX Ingress Controller on a targeted Kubernetes minion.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_nginx_ingress_controller:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.common.k8s-ingress-controller