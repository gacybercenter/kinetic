# Orchestration script to deploy NGINX Ingress Controller on a targeted Kubernetes minion.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_nginx_ingress_controller:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.common.k8s-nginx-controller.install
    - require:
      - test: check_target_minion

# Ensure the target minion is specified
check_target_minion:
  test.fail_without_changes:
    - unless: {{ k8s|length > 0 }}
    - failhard: True
    - name: "No target minion specified in pillar 'k8s'. Please provide a valid minion ID."