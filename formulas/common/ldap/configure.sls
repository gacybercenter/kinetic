include:
  - /formulas/common/ldap/install

# Ensure LDAP connection spec is created
ensure_ldap_config_connect_spec:
  ldap.connect_spec_present:
    - name: ldap_config_connection_setup
    - spec_name: ldap_config_connection
    - connection_dict:
        url: {{ "ldap://" ~ pillar['ldap']['cert']['common_name'] }}
        bind:
          dn: {{ "cn=" ~ pillar['ldap']['admin-user']['name'] ~ "," ~ "dc=rsc,dc=gacyberrange,dc=org" }}
          password: {{ pillar['ldap']['admin-user']['password'] }}
          method: simple
        tls:
          cacertfile: /tmp/ca.pem
          cert_manager_secret: ldap-client-tls
          namespace: {{ pillar['ldap']['namespace'] }}
          starttls: True
    - require:
      - file: ensure_config_ca_cert_file

# Ensure the Root DN is created or updated
ensure_root_dn:
  ldap.root_dn_present:
    - name: {{ pillar['ldap']['root_dn']['dn'] }}
    - root_dn: {{ pillar['ldap']['root_dn']['dn'] }}
    - spec_name: ldap_config_connection
    - attributes:
        o: {{ pillar['ldap']['root_dn']['o'] }}
        objectClass:
          - dcObject
          - organization
    - require:
      - ldap: ensure_ldap_config_connect_spec

# Ensure Organizational Units are created or updated
{% for ou in pillar['ldap']['orgunits'] %}
ensure_ou_{{ ou.name }}:
  ldap.ou_present:
    - name: ou={{ ou.name }}
    - base_dn: {{ pillar['ldap']['root_dn']['dn'] }}
    - spec_name: ldap_config_connection
    - require:
      - ldap: ensure_root_dn
{% endfor %}

# Ensure users are created
{% for user in pillar['ldap']['users'] %}
ensure_user_{{ user.uid }}:
  ldap.user_present:
    - name: ensure_user_{{ user.uid }}
    - spec_name: ldap_config_connection
    - base_dn: ou=users,{{ pillar['ldap']['root_dn']['dn'] }}  # Assuming users are under ou=users
    - cn: {{ user.uid }}
    - uid: {{ user.uid }}
    - sn: {{ user.sn }}
    - description: {{ user.name }}
    - password: {{ user.pass }}
    - require:
      - ldap: ensure_ou_users  # Depend on the users OU being created
{% endfor %}
