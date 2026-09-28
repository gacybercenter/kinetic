# ==========================================================================
# LDAP provisioning: root DN / OUs / users / services / groups, plus optional
# Kubernetes RBAC bindings driven by each user/group's `kubernetes` pillar key.
#
# Expected pillar shape (see docs/kinetic-k8s.md for the RBAC contract):
#
#   ldap:
#     users:
#       - uid: mdanielson
#         cn: "Mark Danielson"
#         sn: Danielson
#         description: "..."         # optional; defaults to cn (LDAP rejects an empty string here)
#         pass: "..."                # optional, GPG-encrypted in practice
#         kubernetes:                # optional
#           cluster_roles: [...]
#           roles:
#             - namespace: default
#               role: view
#           custom_roles:
#             - name: my-role
#               namespace: default   # omit for a ClusterRole
#               rules: [...]
#     services:                      # bind DNs under ou=services
#                                    # (organizationalRole + simpleSecurityObject)
#       - cn: keycloak
#         description: "..."         # optional
#         pass: "..."                # required on create (userPassword);
#                                    # never updated after that
#     groups:
#       - cn: admins
#         members: [mdanielson]      # uids; resolved to member DNs when the
#                                    # uid matches a user defined above
#         kubernetes:                # optional, same shape as above
#           cluster_roles: [...]
#       - cn: se_cyber
#         member_groups: [admins]    # group cns; resolved to group DNs when
#                                    # the cn matches another group defined
#                                    # here. groupOfNames requires at least
#                                    # one member - use member_groups (e.g.
#                                    # nesting the admins group) instead of
#                                    # letting the group default to a
#                                    # self-reference.
#
# Note: `kubernetes.roles`/`kubernetes.cluster_roles` bind an *existing*
# Role/ClusterRole (built-in or one of this entry's own `custom_roles`).
# `kubernetes.custom_roles` creates a Role (if `namespace` is set) or a
# ClusterRole (if not) via k8s.role_present/k8s.clusterrole_present.
#
# OpenStack project/role provisioning for these LDAP groups happens in
# formulas/keystone/federation.sls, not here - this file is applied via a
# standalone orchestration run (orch/k8s-ldap-prov.sls) that doesn't wait
# for Keystone to be reachable, so OpenStack API calls don't belong here.
# ==========================================================================

{% set users_base_dn = "ou=users,dc=rsc,dc=gacyberrange,dc=org" %}
{% set services_base_dn = "ou=services,dc=rsc,dc=gacyberrange,dc=org" %}
{% set groups_base_dn = "ou=groups,dc=rsc,dc=gacyberrange,dc=org" %}
{% set policies_base_dn = "ou=policies,dc=rsc,dc=gacyberrange,dc=org" %}
{% set service_pwd_policy_dn = "cn=service," ~ policies_base_dn %}
{% set ldap_database_dn = pillar['ldap'].get('database_dn', 'olcDatabase={2}mdb,cn=config') %}

{# Map uid -> DN and uid -> ldap state id, for resolving group members that
   are managed here (human users under ou=users). Service accounts are bind
   DNs (organizationalRole), not inetOrgPerson, so they are not group members. #}
{% set uid_to_dn = {} %}
{% set uid_to_state = {} %}
{% for user in pillar['ldap'].get('users', []) %}
{% do uid_to_dn.update({user['uid']: "cn=" ~ user['cn'] ~ "," ~ users_base_dn}) %}
{% do uid_to_state.update({user['uid']: "ldap_user_" ~ user['uid']}) %}
{% endfor %}

{# Map cn -> group DN, for resolving nested group members (member_groups). #}
{% set cn_to_dn = {} %}
{% for group in pillar['ldap'].get('groups', []) %}
{% do cn_to_dn.update({group['cn']: "cn=" ~ group['cn'] ~ "," ~ groups_base_dn}) %}
{% endfor %}

{# ------------------------------------------------------------------------
   Emits Role/ClusterRole + RoleBinding/ClusterRoleBinding states for a
   single user or group's `kubernetes` pillar key.

   entity_kind:   'user' or 'group' (used for state-id namespacing only)
   entity_key:    the uid (for users) or cn (for groups) - used as the
                  Kubernetes Group/User RBAC subject name
   k8s_spec:      the entity's `kubernetes` dict
   subject_kwarg: 'users' or 'groups' - the k8s state kwarg to bind as
   require_id:    the ldap.user_present/ldap.group_present state id to
                  require
   ------------------------------------------------------------------------ #}
{%- macro k8s_rbac_for(entity_kind, entity_key, k8s_spec, subject_kwarg, require_id) -%}
{% set safe_entity = entity_key | lower | replace('_', '-') | replace(' ', '-') %}

{% for custom_role in k8s_spec.get('custom_roles', []) %}
{% set safe_role = custom_role['name'] | lower | replace('_', '-') %}
{% if custom_role.get('namespace') %}
k8s_role_{{ safe_role }}_{{ custom_role['namespace'] }}:
  k8s.role_present:
    - name: {{ custom_role['name'] }}
    - namespace: {{ custom_role['namespace'] }}
    - rules: {{ custom_role['rules'] | tojson }}
    - require:
      - ldap: {{ require_id }}
{% else %}
k8s_clusterrole_{{ safe_role }}:
  k8s.clusterrole_present:
    - name: {{ custom_role['name'] }}
    - rules: {{ custom_role['rules'] | tojson }}
    - require:
      - ldap: {{ require_id }}
{% endif %}
{% endfor %}

{% for role in k8s_spec.get('roles', []) %}
{% set safe_role = role['role'] | lower | replace('_', '-') %}
k8s_{{ entity_kind }}_{{ safe_entity }}_role_{{ role['namespace'] }}_{{ safe_role }}:
  k8s.rolebinding_present:
    - name: {{ safe_entity }}-{{ safe_role }}-binding
    - namespace: {{ role['namespace'] }}
    - role_ref: {{ role['role'] }}
    - role_ref_kind: {{ role.get('kind', 'ClusterRole') }}
    - {{ subject_kwarg }}:
      - {{ entity_key }}
    - require:
      - ldap: {{ require_id }}
{% endfor %}

{% for cluster_role in k8s_spec.get('cluster_roles', []) %}
{% set safe_role = cluster_role | lower | replace('_', '-') %}
k8s_{{ entity_kind }}_{{ safe_entity }}_clusterrole_{{ safe_role }}:
  k8s.clusterrolebinding_group_present:
    - name: {{ safe_entity }}-{{ safe_role }}-clusterbinding
    - cluster_role: {{ cluster_role }}
    - {{ subject_kwarg }}:
      - {{ entity_key }}
    - require:
      - ldap: {{ require_id }}
{% endfor %}
{%- endmacro -%}

# Ensure CA certificate file is present on the minion
ensure_ca_cert_file:
  file.managed:
    - name: /tmp/ca.pem
    - contents: {{ pillar['ldap']['cert']['ca'] | json }}
    - mode: 644
    - user: root
    - group: root
    - makedirs: True

# Ensure LDAP connection spec is created
ensure_ldap_connect_spec:
  ldap.connect_spec_present:
    - name: ldap_connection_setup
    - spec_name: ldap_keycloak_connection
    - connection_dict:
        url: {{ "ldap://" ~ pillar['ldap']['cert']['commonname'] }}
        bind:
          dn: {{ "cn=" ~ pillar['ldap']['admin-user']['name'] ~ "," ~ pillar['ldap']['values']['global']['ldapDomain'] }}
          password: {{ pillar['ldap']['admin-user']['password'] }}
          method: simple
        tls:
          cacertfile: /tmp/ca.pem
          starttls: True
    - require:
      - file: ensure_ca_cert_file

# Ensure LDAP root DN is present
ensure_ldap_root_dn:
  ldap.root_dn_present:
    - name: ldap_root_dn_setup
    - spec_name: ldap_keycloak_connection
    - root_dn: {{ pillar['ldap']['root_dn']['dn'] }}
    - attributes:
        objectClass: ['dcObject', 'organization']
        o: {{ pillar['ldap']['root_dn']['o'] }}
    - require:
      - ldap: ensure_ldap_connect_spec

# Ensure Organizational Units are created
ensure_ldap_ous:
  ldap.ou_present:
    - name: ldap_ou_setup
    - spec_name: ldap_keycloak_connection
    - base_dn: {{ "dc=rsc,dc=gacyberrange,dc=org" }}
    - ous: {{ pillar['ldap']['orgunits']}}
    - require:
      - ldap: ensure_ldap_connect_spec
      - ldap: ensure_ldap_root_dn

# cn=config bind - required to write olcAccess. The data-admin bind used
# above cannot modify cn=config. Password is the same as LDAP_CONFIG_ADMIN_PASSWORD.
ensure_ldap_config_admin_connect_spec:
  ldap.connect_spec_present:
    - name: ldap_config_admin_connection_setup
    - spec_name: ldap_config_admin_connection
    - connection_dict:
        url: {{ "ldap://" ~ pillar['ldap']['cert']['commonname'] }}
        bind:
          dn: {{ "cn=" ~ pillar['ldap']['admin-user']['name'] ~ ",cn=config" }}
          password: {{ pillar['ldap']['admin-user']['password'] }}
          method: simple
        admin_bind:
          dn: {{ "cn=" ~ pillar['ldap']['admin-user']['name'] ~ ",cn=config" }}
          password: {{ pillar['ldap']['admin-user']['password'] }}
          method: simple
        tls:
          cacertfile: /tmp/ca.pem
          starttls: True
    - require:
      - file: ensure_ca_cert_file

{# Grant ou=services bind DNs write on password attrs + the users subtree.
   Inserted at the front of olcAccess so they take precedence over slapd
   defaults; existing rules are left in place. #}
{% set services_password_acl = 'to attrs=userPassword,shadowLastChange,pwdHistory,pwdChangedTime,pwdFailureTime,pwdAccountLockedTime,pwdReset,pwdGraceUseTime by dn.subtree="' ~ services_base_dn ~ '" write by self write by anonymous auth by * none' %}
{% set services_users_acl = 'to dn.subtree="' ~ users_base_dn ~ '" by dn.subtree="' ~ services_base_dn ~ '" write by self read by * none' %}
ensure_services_acls:
  ldap.access_present:
    - name: ldap_services_acls
    - spec_name: ldap_config_admin_connection
    - database_dn: "{{ ldap_database_dn }}"
    - access_rules:
      - {{ services_password_acl | yaml_dquote }}
      - {{ services_users_acl | yaml_dquote }}
    - require:
      - ldap: ensure_ldap_config_admin_connect_spec
      - ldap: ensure_ldap_ous

# ppolicy overlay is required for pwdPolicySubentry on service accounts to
# take effect. Not set as olcPPolicyDefault - that would apply to every
# entry in the database, including human users. Service accounts are bound
# to cn=service via pwdPolicySubentry instead.
ensure_ppolicy_overlay:
  ldap.overlay_present:
    - name: ldap_ppolicy_overlay
    - spec_name: ldap_config_admin_connection
    - database_dn: "{{ ldap_database_dn }}"
    - overlays:
      - name: ppolicy
        index: 0
        attributes:
          objectClass:
            - olcOverlayConfig
            - olcPPolicyConfig
          olcOverlay: ppolicy
          olcPPolicyHashCleartext: "FALSE"
          olcPPolicyUseLockout: "FALSE"
    - require:
      - ldap: ensure_ldap_config_admin_connect_spec

ensure_policies_ou:
  ldap.ou_present:
    - name: ou=policies,dc=rsc,dc=gacyberrange,dc=org
    - spec_name: ldap_keycloak_connection
    - base_dn: dc=rsc,dc=gacyberrange,dc=org
    - ous:
      - name: policies
    - require:
      - ldap: ensure_ldap_ous

# Service-account password policy. OpenLDAP does not inherit pwdPolicy from
# a parent OU - each bind DN under ou=services is pointed at this object
# via pwdPolicySubentry.
ensure_service_pwd_policy:
  ldap.root_dn_present:
    - name: {{ service_pwd_policy_dn }}
    - spec_name: ldap_keycloak_connection
    - root_dn: {{ service_pwd_policy_dn }}
    - attributes:
        objectClass:
          - top
          - person
          - pwdPolicy
        cn: service
        sn: service
        pwdAttribute: userPassword
        pwdAllowUserChange: "TRUE"
        pwdCheckQuality: "0"
        pwdInHistory: "0"
        pwdLockout: "FALSE"
        pwdMaxAge: "0"
        pwdMinAge: "0"
        pwdMinLength: "12"
        pwdMustChange: "FALSE"
        pwdSafeModify: "FALSE"
    - require:
      - ldap: ensure_policies_ou
      - ldap: ensure_ppolicy_overlay

# ==========================================================================
# Users
# ==========================================================================
{% for user in pillar['ldap'].get('users', []) %}

ldap_user_{{ user['uid'] }}:
  ldap.user_present:
    - name: ldap_user_{{ user['uid'] }}
    - spec_name: ldap_keycloak_connection
    - base_dn: {{ users_base_dn }}
    - uid: {{ user['uid'] }}
    - cn: {{ user['cn'] | yaml_dquote }}
    - sn: {{ user.get('sn', user['uid']) | yaml_dquote }}
    - description: {{ user.get('description', user['cn']) | yaml_dquote }}
{%- if user.get('pass') %}
    - password: {{ user['pass'] | yaml_dquote }}
{%- endif %}
    - require:
      - ldap: ensure_ldap_connect_spec
      - ldap: ensure_ldap_ous

{% if user.get('kubernetes') %}
{{ k8s_rbac_for('user', user['uid'], user['kubernetes'], 'users', 'ldap_user_' ~ user['uid']) }}
{% endif %}
{% endfor %}

# ==========================================================================
# Services (bind DNs under ou=services)
# ==========================================================================
{% for service in pillar['ldap'].get('services', []) %}
{% set service_cn = service.get('cn', service.get('uid')) %}

ldap_service_{{ service_cn }}:
  ldap.service_present:
    - name: ldap_service_{{ service_cn }}
    - spec_name: ldap_keycloak_connection
    - base_dn: {{ services_base_dn }}
    - cn: {{ service_cn | yaml_dquote }}
    - pwd_policy_subentry: {{ service_pwd_policy_dn }}
{%- if service.get('description') %}
    - description: {{ service['description'] | yaml_dquote }}
{%- endif %}
{%- if service.get('pass') %}
    - password: {{ service['pass'] | yaml_dquote }}
{%- endif %}
    - require:
      - ldap: ensure_ldap_connect_spec
      - ldap: ensure_ldap_ous
      - ldap: ensure_service_pwd_policy

{% if service.get('kubernetes') %}
{{ k8s_rbac_for('service', service_cn, service['kubernetes'], 'users', 'ldap_service_' ~ service_cn) }}
{% endif %}
{% endfor %}

# ==========================================================================
# Groups
# ==========================================================================
{% for group in pillar['ldap'].get('groups', []) %}
{% set member_dns = [] %}
{% for member in group.get('members', []) %}
{% do member_dns.append(uid_to_dn.get(member, member)) %}
{% endfor %}
{% for member_group in group.get('member_groups', []) %}
{% do member_dns.append(cn_to_dn.get(member_group, member_group)) %}
{% endfor %}

ldap_group_{{ group['cn'] }}:
  ldap.group_present:
    - name: ldap_group_{{ group['cn'] }}
    - spec_name: ldap_keycloak_connection
    - base_dn: {{ groups_base_dn }}
    - cn: {{ group['cn'] | yaml_dquote }}
{%- if group.get('description') %}
    - description: {{ group['description'] | yaml_dquote }}
{%- endif %}
    - members: {{ member_dns | tojson }}
    - require:
      - ldap: ensure_ldap_connect_spec
      - ldap: ensure_ldap_ous
{%- for member in group.get('members', []) if member in uid_to_state %}
      - ldap: {{ uid_to_state[member] }}
{%- endfor %}
{%- for member_group in group.get('member_groups', []) if member_group in cn_to_dn and member_group != group['cn'] %}
      - ldap: ldap_group_{{ member_group }}
{%- endfor %}

{% if group.get('kubernetes') %}
{{ k8s_rbac_for('group', group['cn'], group['kubernetes'], 'groups', 'ldap_group_' ~ group['cn']) }}
{% endif %}
{% endfor %}
