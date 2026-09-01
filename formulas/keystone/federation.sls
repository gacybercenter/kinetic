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

{# Domain that federated OIDC group memberships/role-assignments are scoped
   to. This must be a SQL-backed domain (default: Default), NOT the
   LDAP-backed realm_domain ('rsc'). Keystone's federated shadow-user group
   membership tracking (ExpiringUserGroupMembership) writes a row with a
   foreign key into the SQL `group` table on every federated login - this
   fails with a DB IntegrityError for groups that live in a domain using a
   domain-specific LDAP identity driver, since those groups never have a
   corresponding row in the SQL group table. See openstack_federated_group_*
   below, which creates empty SQL-backed "shadow" groups (same names as the
   real LDAP groups) purely so federated logins have somewhere valid to
   land - Keystone manages their membership dynamically per-login based on
   the IdP's claims, so these groups are never populated with members here. #}
{% set federated_group_domain = oidc.get('federated_group_domain', 'Default') %}

{# mod_wsgi drops the HTTP_OIDC_PREFERRED_USERNAME header, so the username
   claim must be read from OIDC-preferred_username instead (per keystone's
   mod_auth_openidc debug dump). The second rule is a fallback for users
   who authenticate without a groups claim.

   The first rule's local entry uses the plural groups form (a bare
   groups: '{1}' key, sibling to domain) rather than the singular
   group: {name: '{1}', domain: ...} form, because HTTP_OIDC_GROUPS is a
   multi-valued claim - a user can belong to more than one Keycloak group.
   The singular form only handles one atomic value; when a user has
   multiple groups, Keystone still splits the assertion into a list, but
   the singular form then tries to use that whole Python list as a single
   literal group name (breaks the group lookup).

   The groups rule targets federated_group_domain (SQL-backed), not
   realm_domain (LDAP-backed) - see the comment on federated_group_domain
   above for why. #}
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
            {
                'group': {
                    'name': '{1}',
                    'domain': {'name': federated_group_domain},
                }
            },
        ],
        'remote': [
            {'type': 'OIDC-preferred_username'},
            {'type': 'HTTP_OIDC_GROUPS'},
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
   per unique project name below. federated_group_names collects every
   group referenced this way, so we can also emit exactly one
   openstack_federated_group_* state per unique group name.

   `openstack.projects` may be a single mapping (shorthand for one project)
   or a list of mappings.

   Never creates OpenStack users - this is group-driven only. This lives
   here (rather than in formulas/common/ldapadmin/prov.sls, which
   provisions the LDAP groups themselves) because prov.sls is applied via
   a standalone orchestration run (orch/k8s-ldap-prov.sls) that has no
   guarantee Keystone is reachable - project/role assignment calls would
   fail if Keystone isn't up yet. federation.sls already gates on
   keystone_available.
   ------------------------------------------------------------------------ #}
{% set projects_map = {} %}
{% set federated_group_names = [] %}
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
{% if group['cn'] not in federated_group_names %}
{% do federated_group_names.append(group['cn']) %}
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

# Empty SQL-backed "shadow" groups (same names as the real LDAP groups),
# purely so Keystone's federated group-membership tracking has a valid SQL
# `group` row to reference. Never populated with static members here -
# Keystone adds/removes federated users' membership dynamically per-login
# based on the IdP's claims. See the federated_group_domain comment above.
{% for group_name in federated_group_names %}
openstack_federated_group_{{ group_name }}:
  kinetic_openstack.group_present:
    - name: {{ group_name }}
    - domain_name: {{ federated_group_domain }}
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: keystone_available
{% endfor %}

# Map Keycloak's OIDC claims onto the existing LDAP user (in the 'rsc'
# domain) and the SQL-backed shadow groups created above. Never creates
# users - LDAP already owns them.
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

# Projects + role assignments for the shadow groups above. Exactly one
# project_present state is emitted per unique project name (see
# projects_map above), even if multiple groups reference it.
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
    - group_domain: {{ federated_group_domain }}
    - project_domain: {{ entry['domain'] }}
    - cloud: {{ cloud_name }}
    - require:
      - kinetic_openstack: openstack_project_{{ safe_project }}
      - kinetic_openstack: openstack_federated_group_{{ assignment['group'] }}
{% endfor %}
{% endfor %}
