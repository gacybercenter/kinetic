# ==========================================================================
# LDAP provisioning: root DN / OUs / users / groups, plus optional Kubernetes
# RBAC bindings driven by each user/group's `kubernetes` pillar key.
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
# ==========================================================================

{% set users_base_dn = "ou=users,dc=rsc,dc=gacyberrange,dc=org" %}
{% set groups_base_dn = "ou=groups,dc=rsc,dc=gacyberrange,dc=org" %}

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
# Groups
# ==========================================================================
{% for group in pillar['ldap'].get('groups', []) %}
{% set member_dns = [] %}
{% for member in flat_members.get(group['cn'], []) %}
{% do member_dns.append(uid_to_dn.get(member, member)) %}
{% endfor %}

{% for child in group.get('member_groups', []) if child not in cn_to_dn %}
ldap_group_{{ group['cn'] }}_missing_{{ child }}:
  test.fail_without_changes:
    - name: {{ child }}
    - comment: "ldap.groups {{ group['cn'] }} member_groups entry {{ child }} is not a group in this pillar"
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
{%- for member in flat_members.get(group['cn'], []) if member in uid_to_dn %}
      - ldap: ldap_user_{{ member }}
{%- endfor %}

{% if group.get('kubernetes') %}
{{ k8s_rbac_for('group', group['cn'], group['kubernetes'], 'groups', 'ldap_group_' ~ group['cn']) }}
{% endif %}
{% endfor %}
