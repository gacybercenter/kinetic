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
   mod_auth_openidc debug dump).

   'type': 'local' on the user rule means the federated login resolves
   directly onto an ALREADY-EXISTING Keystone user (matched by name +
   domain) instead of creating an ephemeral/shadow user. Since
   psa-mdanielson etc. already exist as real users in the LDAP-backed
   realm_domain ('rsc'), authorization then comes from that REAL user's
   REAL LDAP group memberships/role assignments - no separate federation
   group-mapping/shadowing is involved at all.

   This deliberately avoids the ephemeral-user path: Keystone's federated
   shadow-user group-membership tracking (ExpiringUserGroupMembership)
   unconditionally writes a row with a foreign key into the SQL `group`
   table for every group_id resolved from a HTTP_OIDC_GROUPS mapping - which
   fails with a DB IntegrityError for domain-specific LDAP-backed groups
   (they have no corresponding row in the SQL group table). That code path
   only runs for ephemeral users, so 'type': 'local' sidesteps it entirely
   - which is why role assignments below target the real LDAP groups in
   realm_domain, not a separate SQL-backed "shadow" domain. #}
{% set default_mapping_rules = [
    {
        'local': [
            {
                'user': {
                    'type': 'local',
                    'name': '{0}',
                    'domain': {'name': realm_domain},
                }
            },
        ],
        'remote': [
            {'type': 'OIDC-preferred_username'},
        ],
    },
] %}
{% set mapping_rules = oidc.get('mapping_rules', default_mapping_rules) %}

{# ------------------------------------------------------------------------
   Build a single deduplicated map of OpenStack project -> role assignments
   across ALL LDAP groups' `openstack` pillar keys, e.g.:

     ldap:
       groups:
         - cn: admins
           openstack:
             projects:
               - name: se_cyber
                 roles: [admin]
         - cn: se_cyber
           openstack:
             projects:
               roles: [member]      # name defaults to this group's cn verbatim

   Multiple groups can reference the *same* project (as above - both
   'admins' and 'se_cyber' resolve to project 'se_cyber'). Emitting a
   kinetic_openstack.project_present state per *group* (instead of per
   unique project) would render the same state ID twice and fail with
   "found conflicting ID" - so every group's projects are folded into
   projects_map first, and exactly one project_present state is emitted
   per unique project name below.

   `openstack.projects` may be a single mapping (shorthand for one project)
   or a list of mappings.

   Never creates OpenStack users or groups - this is group-driven only,
   using the REAL LDAP groups that formulas/common/ldapadmin/prov.sls
   already provisions (matched by the same cn, in realm_domain). This lives
   here (rather than in prov.sls) because prov.sls is applied via a
   standalone orchestration run (orch/k8s-ldap-prov.sls) that has no
   guarantee Keystone is reachable - project/role assignment calls would
   fail if Keystone isn't up yet. federation.sls already gates on
   keystone_available.
   ------------------------------------------------------------------------ #}
{% set projects_map = {} %}
{% for group in pillar.get('ldap', {}).get('groups', []) %}
{% set os_spec = group.get('openstack') %}
{% if os_spec %}
{% set projects = os_spec.get('projects', []) %}
{% if projects is mapping %}
{% set projects = [projects] %}
{% endif %}
{% for project in projects %}
{% set project_name = project.get('name', group['cn']) %}
{% set entry = projects_map.setdefault(project_name, {'description': None, 'domain': 'Default', 'assignments': []}) %}
{% if project.get('description') %}
{% do entry.update({'description': project['description']}) %}
{% endif %}
{% if project.get('domain') %}
{% do entry.update({'domain': project['domain']}) %}
{% endif %}
{% if project.get('roles') %}
{% set roles = project['roles'] %}
{% elif project.get('role') %}
{% set roles = [project['role']] %}
{% else %}
{% set roles = ['member'] %}
{% endif %}
{% for role in roles %}
{% set assignment = {'group': group['cn'], 'role': role} %}
{% if assignment not in entry['assignments'] %}
{% do entry['assignments'].append(assignment) %}
{% endif %}
{% endfor %}
{% endfor %}
{% endif %}
{% endfor %}

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
# by LDAP) so federated logins resolve to the LDAP users already in that
# domain, instead of a brand new IdP-owned domain. This never creates the
# domain itself - domain rsc must already exist.
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

# Map Keycloak's OIDC claims onto the existing LDAP user in the 'rsc'
# domain (see the 'type': 'local' comment above). Never creates users -
# LDAP already owns them.
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

# Projects + role assignments for the REAL LDAP groups (formulas/common/
# ldapadmin/prov.sls provisions the groups themselves in realm_domain).
# Exactly one project_present state is emitted per unique project name
# (see projects_map above), even if multiple groups reference it.
{% for project_name, entry in projects_map.items() %}
{% set safe_project = project_name | lower | replace('_', '-') | replace(' ', '-') %}
openstack_project_{{ safe_project }}:
  kinetic_openstack.project_present:
    - name: {{ project_name }}
    - description: {{ (entry['description'] or ("Project for " ~ project_name)) | yaml_dquote }}
    - enabled: True
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: keystone_available

{% for assignment in entry['assignments'] %}
openstack_role_assignment_{{ safe_project }}_{{ assignment['group'] }}_{{ assignment['role'] }}:
  kinetic_openstack.role_assignment_present:
    - role_name: {{ assignment['role'] }}
    - project_name: {{ project_name }}
    - group_name: {{ assignment['group'] }}
    - group_domain: {{ realm_domain }}
    - project_domain: {{ entry['domain'] }}
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: openstack_project_{{ safe_project }}
{% endfor %}
{% endfor %}
