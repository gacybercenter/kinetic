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
          ca_certs_file: /tmp/ca.pem
          starttls: True
    - require:
      - file: ensure_ca_cert_file

# Ensure LDAP root DN is present
{% set root_dn_key = pillar['ldap']['root_dn'].keys() | first %}
{% set root_dn_attrs = pillar['ldap']['root_dn'][root_dn_key] %}
{% set root_dn_parts = root_dn_key.split('.') %}
{% set root_dn = 'dc=' + root_dn_parts|join(',dc=') %}
{% set org_name = root_dn_attrs.get('o', 'Example Organization') %}
ensure_ldap_root_dn:
  ldap.root_dn_present:
    - name: ldap_root_dn_setup
    - spec_name: ldap_keycloak_connection
    - root_dn: {{ root_dn }}
    - attributes:
        objectClass: ['dcObject', 'organization']
        o: {{ org_name }}
    - require:
      - ldap: ensure_ldap_connect_spec
