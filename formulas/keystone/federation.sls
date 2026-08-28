include:
  - /formulas/keystone/configure

{% set oidc = pillar.get('osh', {}).get('keystone_oidc', {}) %}
{% set realm_domain = oidc.get('realm', 'rsc') %}
{% set idp_name = oidc.get('idp_name', 'keycloak') %}
{% set protocol_id = oidc.get('protocol_id', 'openid') %}
{% set mapping_id = oidc.get('mapping_id', 'keycloak_openid') %}
{% set cloud_name = oidc.get('cloud', 'rsc') %}
{% set health_timeout = oidc.get('health_check_timeout', 180) %}
{% set health_interval = oidc.get('health_check_interval', 5) %}
{% set remote_id = oidc.get('remote_id', oidc.get('provider_metadata_url', '').split('/.well-known')[0]) %}

{# mod_wsgi drops the HTTP_OIDC_PREFERRED_USERNAME header, so the username
   claim must be read from OIDC-preferred_username instead (per keystone's
   mod_auth_openidc debug dump). The second rule is a fallback for users
   who authenticate without a groups claim. #}
{% set default_mapping_rules = [
    {
        'local': [
            {'user': {'name': '{0}', 'domain': {'name': realm_domain}}},
            {'group': {'name': '{1}', 'domain': {'name': realm_domain}}},
        ],
        'remote': [
            {'type': 'OIDC-preferred_username'},
            {'type': 'HTTP_OIDC_GROUPS'},
        ],
    },
    {
        'local': [
            {'user': {'name': '{0}', 'domain': {'name': realm_domain}}},
        ],
        'remote': [
            {'type': 'OIDC-preferred_username'},
        ],
    },
] %}
{% set mapping_rules = oidc.get('mapping_rules', default_mapping_rules) %}

{# ------------------------------------------------------------------------
   Emits kinetic_openstack.project_present + role_assignment_present states
   for a single LDAP group's `openstack` pillar key. Ensures the named
   projects exist and assigns the given role(s) to this LDAP group
   (Keystone domain {{ realm_domain }}) on them. Never creates OpenStack
   users - this is group-driven only, matching how that domain is backed
   by the LDAP tree provisioned in formulas/common/ldapadmin/prov.sls.

   This lives here (rather than in prov.sls) because prov.sls is applied
   via a standalone orchestration run (orch/k8s-ldap-prov.sls) that has no
   guarantee Keystone is reachable - project/role assignment calls would
   fail if Keystone isn't up yet. federation.sls already gates on
   keystone_available.

   group_cn:  the group's cn - used as the Keystone group name (must match
              the LDAP group cn 1:1, since {{ realm_domain }} is LDAP-backed)
   os_spec:   the group's `openstack` dict, e.g.:

                openstack:
                  projects:
                    - name: my-project      # optional, defaults to this group's cn
                                             # verbatim (so it matches whatever
                                             # name another group's role
                                             # assignment onto this same
                                             # project would need to use)
                      description: "..."    # optional, defaults to "Project for <name>"
                      domain: Default       # optional, project's domain, defaults to Default
                      roles: [member]       # optional, defaults to [member]

              `projects` may also be a single mapping (rather than a list of
              one) for the common one-project-per-group case, e.g.:

                openstack:
                  projects:
                    roles: [member]
   ------------------------------------------------------------------------ #}
{%- macro openstack_projects_for(group_cn, os_spec) -%}
{% set projects = os_spec.get('projects', []) %}
{% if projects is mapping %}
{% set projects = [projects] %}
{% endif %}
{% for project in projects %}
{% set project_name = project.get('name', group_cn) %}
{% set safe_project = project_name | lower | replace('_', '-') | replace(' ', '-') %}
{% set project_domain = project.get('domain', 'Default') %}
{% if project.get('roles') %}
{% set roles = project['roles'] %}
{% elif project.get('role') %}
{% set roles = [project['role']] %}
{% else %}
{% set roles = ['member'] %}
{% endif %}

openstack_project_{{ safe_project }}:
  kinetic_openstack.project_present:
    - name: {{ project_name }}
    - description: {{ project.get('description', "Project for " ~ project_name) | yaml_dquote }}
    - enabled: True
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: keystone_available

{% for role in roles %}
openstack_role_assignment_{{ safe_project }}_{{ group_cn }}_{{ role }}:
  kinetic_openstack.role_assignment_present:
    - role_name: {{ role }}
    - project_name: {{ project_name }}
    - group_name: {{ group_cn }}
    - group_domain: {{ realm_domain }}
    - project_domain: {{ project_domain }}
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: openstack_project_{{ safe_project }}
{% endfor %}
{% endfor %}
{%- endmacro -%}

# Gate: don't attempt any federation setup until Keystone is actually
# reachable and issuing tokens. Helm reporting the release as deployed
# doesn't guarantee the external HTTPRoute/Ingress/DNS path is ready yet.
keystone_available:
  kinetic_openstack.health_check:
    - cloud: {{ cloud_name }}
    - timeout: {{ health_timeout }}
    - interval: {{ health_interval }}
    - require:
      - k8s_helm: install_keystone

# Scope the Keycloak identity provider to the existing 'rsc' domain (owned
# by LDAP) so federated logins resolve to the LDAP users/groups already in
# that domain, instead of a brand new IdP-owned domain. This never creates
# the domain itself - domain rsc must already exist.
keystone_keycloak_idp:
  kinetic_openstack.identity_provider_present:
    - name: {{ idp_name }}
    - domain_name: {{ realm_domain }}
    - enabled: true
    - remote_ids:
      - {{ remote_id }}
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: keystone_available

# Map Keycloak's OIDC claims onto existing LDAP users/groups in the 'rsc'
# domain. Never creates users or groups - LDAP already owns them.
keystone_keycloak_mapping:
  kinetic_openstack.mapping_present:
    - name: {{ mapping_id }}
    - rules: {{ mapping_rules | tojson }}
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: keystone_available

keystone_keycloak_protocol:
  kinetic_openstack.federation_protocol_present:
    - name: {{ protocol_id }}
    - idp_name: {{ idp_name }}
    - mapping_id: {{ mapping_id }}
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: keystone_keycloak_idp
      - kinetic_openstack: keystone_keycloak_mapping

# Projects + role assignments for LDAP groups. formulas/common/ldapadmin's
# prov.sls provisions the LDAP groups themselves; the OpenStack side lives
# here instead, since it needs Keystone to actually be reachable. Driven by
# each group's `openstack` key in the same pillar['ldap']['groups'] list
# consumed by prov.sls - see the openstack_projects_for macro above.
{% for group in pillar.get('ldap', {}).get('groups', []) %}
{% if group.get('openstack') %}
{{ openstack_projects_for(group['cn'], group['openstack']) }}
{% endif %}
{% endfor %}
