# Orchestration to sync LDAP group membership (and K8s RBAC) with the
# corresponding OpenStack role assignments.
#
# Usage:
#   salt-run state.orchestrate orch.ldap-keystone-sync pillar='{"k8s": "master-rsc-0"}'
#
# This is the single command you run after changing ldap:groups[] in pillar
# when you want both the LDAP side and the Keystone side updated together.

{% set k8s = salt['pillar.get']('k8s') %}

provision_ldap_and_k8s_rbac:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.common.ldapadmin.prov

sync_keystone_role_assignments:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.keystone.federation
    - require:
      - salt: provision_ldap_and_k8s_rbac
