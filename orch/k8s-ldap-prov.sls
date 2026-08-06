# Orchestration script to deploy Kubernetes authentication and storage components.
# This script uses the k8s pillar value to target the minion where the installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

provision_ldap:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.common.ldapadmin.prov
