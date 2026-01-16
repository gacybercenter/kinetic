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
        url: {{ "ldap://" ~ pillar['ldap']['cert']['common_name'] }}
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

# Ensure Users are created
ensure_ldap_users:
  ldap.user_present:
    - name: ldap_user_setup
    - spec_name: ldap_keycloak_connection
    - base_dn: {{ "ou=users,dc=rsc,dc=gacyberrange,dc=org" }}
    - users: {{ pillar['ldap'].get('users', []) }}
    - require:
      - ldap: ensure_ldap_connect_spec
      - ldap: ensure_ldap_ous

# Ensure Groups are created
ensure_ldap_groups:
  ldap.group_present:
    - name: ldap_group_setup
    - spec_name: ldap_keycloak_connection
    - base_dn: {{ "ou=groups,dc=rsc,dc=gacyberrange,dc=org" }}
    - groups: {{ pillar['ldap'].get('groups', []) }}
    - require:
      - ldap: ensure_ldap_connect_spec
      - ldap: ensure_ldap_ous
      - ldap: ensure_ldap_users
