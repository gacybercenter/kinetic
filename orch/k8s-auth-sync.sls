# Orchestration to sync LDAP group membership (and K8s RBAC) with the
# corresponding OpenStack role assignments.
#
# Usage:
#   salt-run state.orchestrate orch.k8s-auth-sync pillar='{"k8s": "master-rsc-0"}'
#
# This is the single command you run after changing ldap:groups[] in pillar
# when you want both the LDAP side and the Keystone side updated together.
#
# LDAP should remain the single source of truth for authorization wherever
# possible - both formulas below read the exact same pillar['ldap']['groups']/
# ['users'] lists, rather than maintaining separate group/membership data per
# service. Prefer extending that shared pillar (and this orchestration) over
# introducing a service-specific membership source when adding new services
# to sync in the future.

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
