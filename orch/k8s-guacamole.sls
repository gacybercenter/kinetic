# Orchestration script to deploy Apache Guacamole (helmforge chart) with a
# CloudNativePG cluster and an HTTPRoute. TLS terminates on the Gateway.
#
#   salt-run state.orchestrate orch.k8s-guacamole pillar='{"k8s": "master-rsc-0"}'

{% set k8s = salt['pillar.get']('k8s') %}

deploy_guacamole:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.guacamole
