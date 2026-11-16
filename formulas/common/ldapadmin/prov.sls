# ==========================================================================
# LDAP provisioning: root DN / OUs / users / services / groups, plus optional
# Kubernetes RBAC bindings driven by each user/group's `kubernetes` pillar key.
#
# Expected pillar shape (see docs/kinetic-k8s.md for the RBAC contract):
#
#   ldap:
#     users:
#       - givenName: Michael           # required, with sn and mail
#         sn: Carpenter                # required
#         mail: mcarpenter@augusta.edu # required
#         uid: mcarpenter              # optional; first letter of givenName + sn
#         cn: mcarpenter               # optional; same default as uid. This is the RDN.
#         description: "..."         # optional; defaults to cn
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
#       - cn: os-enabled
#         member_groups: [admins]    # flattened to the member uids of those
#                                    # groups before the LDAP group is written.
#                                    # Keycloak does not expand a group DN in
#                                    # member. A missing child group fails.
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

{# givenName, sn, and mail are required. uid and cn default to the first
   letter of givenName plus sn, lowercased, with spaces and apostrophes
   removed: Michael Carpenter -> mcarpenter. An explicit uid or cn is kept.
   cn is the RDN, so omitting it on an existing user renames the entry. #}
{% set ldap_users = [] %}
{% for user in pillar['ldap'].get('users', []) %}
{% set given_name = (user.get('givenName') or '') | trim %}
{% set surname = (user.get('sn') or '') | trim %}
{% set mail = (user.get('mail') or '') | trim %}
{% set derived = (given_name[:1] ~ surname) | lower | replace(' ', '') | replace("'", '') | replace('-', '') %}
{% set missing = [] %}
{% if not given_name %}{% do missing.append('givenName') %}{% endif %}
{% if not surname %}{% do missing.append('sn') %}{% endif %}
{% if not mail %}{% do missing.append('mail') %}{% endif %}
{% set uid = user.get('uid') or derived %}
{% set cn = user.get('cn') or derived %}
{% do ldap_users.append({
  'uid': uid,
  'cn': cn,
  'sn': surname,
  'givenName': given_name,
  'mail': mail,
  'description': user.get('description', cn),
  'pass': user.get('pass'),
  'kubernetes': user.get('kubernetes'),
  'missing': missing,
}) %}
{% endfor %}

{# Map uid -> user DN, for resolving group members that are managed here. #}
{% set uid_to_dn = {} %}
{% for user in ldap_users if not user['missing'] %}
{% do uid_to_dn.update({user['uid']: "cn=" ~ user['cn'] ~ "," ~ users_base_dn}) %}
{% do uid_to_state.update({user['uid']: "ldap_user_" ~ user['uid']}) %}
{% endfor %}

{# Map cn -> group DN, and flatten member_groups to user uids. A child
   group listed later in the pillar is still expanded. Cycles stop once no
   new uid is added. The LDAP member attribute gets user DNs only. #}
{% set cn_to_dn = {} %}
{% set group_direct = {} %}
{% set group_children = {} %}
{% for group in pillar['ldap'].get('groups', []) %}
{% do cn_to_dn.update({group['cn']: "cn=" ~ group['cn'] ~ "," ~ groups_base_dn}) %}
{% do group_direct.update({group['cn']: group.get('members', [])}) %}
{% do group_children.update({group['cn']: group.get('member_groups', [])}) %}
{% endfor %}
{% set flat_members = {} %}
{% for cn, members in group_direct.items() %}
{% set seen = [] %}
{% for member in members %}
{% if member not in seen %}
{% do seen.append(member) %}
{% endif %}
{% endfor %}
{% do flat_members.update({cn: seen}) %}
{% endfor %}
{% for _pass in range(group_children | length) %}
{% for cn, children in group_children.items() %}
{% for child in children if child in flat_members %}
{% for member in flat_members[child] %}
{% if member not in flat_members[cn] %}
{% do flat_members[cn].append(member) %}
{% endif %}
{% endfor %}
{% endfor %}
{% endfor %}
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

{# Grant ou=services bind DNs write so they can change user passwords and
   maintain ppolicy operational attrs, plus read on groups (Keycloak's
   group-ldap-mapper searches groups.dn at login; OpenLDAP reports a denied
   search base as LDAP 32 No Such Object).
     {0} userPassword/shadowLastChange: services write, self write, anon auth
     {1} ppolicy operational attrs: services write, self read (not write -
         users must not be able to clear lockout/history themselves)
     {2} ou=users subtree: services write, self read
     {3} ou=groups subtree: services read (mapper is READ_ONLY)
   Inserted at the front of olcAccess so they take precedence over slapd
   defaults; existing rules are left in place. #}
{% set services_password_acl = 'to attrs=userPassword,shadowLastChange by dn.subtree="' ~ services_base_dn ~ '" write by self write by anonymous auth by * none' %}
{% set services_ppolicy_acl = 'to attrs=pwdHistory,pwdChangedTime,pwdFailureTime,pwdAccountLockedTime,pwdReset,pwdGraceUseTime by dn.subtree="' ~ services_base_dn ~ '" write by self read by * none' %}
{% set services_users_acl = 'to dn.subtree="' ~ users_base_dn ~ '" by dn.subtree="' ~ services_base_dn ~ '" write by self read by * none' %}
{% set services_groups_acl = 'to dn.subtree="' ~ groups_base_dn ~ '" by dn.subtree="' ~ services_base_dn ~ '" read by * none' %}
ensure_services_acls:
  ldap.access_present:
    - name: ldap_services_acls
    - spec_name: ldap_config_admin_connection
    - database_dn: "{{ ldap_database_dn }}"
    - access_rules:
      - {{ services_password_acl | yaml_dquote }}
      - {{ services_ppolicy_acl | yaml_dquote }}
      - {{ services_users_acl | yaml_dquote }}
      - {{ services_groups_acl | yaml_dquote }}
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
{% for user in ldap_users %}
{% if user['missing'] %}
ldap_user_missing_{{ loop.index }}:
  test.fail_without_changes:
    - name: ldap user {{ loop.index }}
    - comment: "ldap.users entry {{ loop.index }} is missing {{ user['missing'] | join(', ') }}. givenName, sn, and mail are required."
{% else %}
ldap_user_{{ user['uid'] }}:
  ldap.user_present:
    - name: ldap_user_{{ user['uid'] }}
    - spec_name: ldap_keycloak_connection
    - base_dn: {{ users_base_dn }}
    - uid: {{ user['uid'] | yaml_dquote }}
    - cn: {{ user['cn'] | yaml_dquote }}
    - sn: {{ user['sn'] | yaml_dquote }}
    - given_name: {{ user['givenName'] | yaml_dquote }}
    - mail: {{ user['mail'] | yaml_dquote }}
    - description: {{ user['description'] | yaml_dquote }}
{%- if user.get('pass') %}
    - password: {{ user['pass'] | yaml_dquote }}
{%- endif %}
    - require:
      - ldap: ensure_ldap_connect_spec
      - ldap: ensure_ldap_ous

{% if user.get('kubernetes') %}
{{ k8s_rbac_for('user', user['uid'], user['kubernetes'], 'users', 'ldap_user_' ~ user['uid']) }}
{% endif %}
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
{% set unresolved = [] %}
{% for member in flat_members.get(group['cn'], []) if member not in uid_to_dn %}
{% do unresolved.append(member) %}
{% endfor %}
{% set member_dns = [] %}
{% for member in flat_members.get(group['cn'], []) if member in uid_to_dn %}
{% do member_dns.append(uid_to_dn[member]) %}
{% endfor %}

{% for child in group.get('member_groups', []) if child not in cn_to_dn %}
ldap_group_{{ group['cn'] }}_missing_{{ child }}:
  test.fail_without_changes:
    - name: {{ child }}
    - comment: "ldap.groups {{ group['cn'] }} member_groups entry {{ child }} is not a group in this pillar"
{% endfor %}

{% if unresolved %}
{# A bare uid is not a DN. Skipping the update leaves the existing member
   list alone instead of dropping people who failed user validation. #}
ldap_group_{{ group['cn'] }}_unresolved:
  test.fail_without_changes:
    - name: {{ group['cn'] }}
    - comment: "ldap.groups {{ group['cn'] }} members are not resolvable users: {{ unresolved | join(', ') }}. Each needs givenName, sn, and mail, or an explicit uid and cn."
{% else %}
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
{%- for member in flat_members.get(group['cn'], []) if member in uid_to_dn %}
      - ldap: ldap_user_{{ member }}
{%- endfor %}

{% if group.get('kubernetes') %}
{{ k8s_rbac_for('group', group['cn'], group['kubernetes'], 'groups', 'ldap_group_' ~ group['cn']) }}
{% endif %}
{% endif %}
{% endfor %}

{# Pull the directory into Keycloak after the writes. Full sync, not the
   changed-users sync: a group member update does not touch the user entry.
   Skip when this pillar has no Keycloak admin connection. #}
{% set kc = pillar.get('res-k8s', {}).get('keycloak', {}) %}
{% set kc_conn = kc.get('connection', {}) %}
{% set synced_groups = [] %}
{% for group in pillar['ldap'].get('groups', []) %}
{% set unresolved = [] %}
{% for member in flat_members.get(group['cn'], []) if member not in uid_to_dn %}
{% do unresolved.append(member) %}
{% endfor %}
{% if not unresolved %}
{% do synced_groups.append(group['cn']) %}
{% endif %}
{% endfor %}
{% if kc_conn %}
{% for realm_name, realm in pillar.get('ldap', {}).get('realms', {}).items() %}
{% for fed_key in realm.get('user_federation', {}) %}
keycloak_ldap_sync_{{ realm_name }}_{{ fed_key }}:
  keycloak.ldap_federation_sync:
    - name: {{ fed_key }}
    - realm: {{ realm_name }}
    - federation_name: {{ fed_key }}
    - action: triggerFullSync
    - timeout: 120
    - keycloak_addr: {{ kc_conn.get('keycloak_addr', 'k8s://keycloak/keycloak-service:8443') }}
    - namespace: {{ kc_conn.get('namespace', 'keycloak') }}
    - secret_name: {{ kc_conn.get('secret_name', 'keycloak-admin') }}
    - verify: {{ kc_conn.get('verify', false) }}
    - require:
      - ldap: ensure_ldap_ous
{%- for group_cn in synced_groups %}
      - ldap: ldap_group_{{ group_cn }}
{%- endfor %}
{% endfor %}
{% endfor %}
{% endif %}
