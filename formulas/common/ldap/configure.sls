include:
  - /formulas/common/ldap/install

# Ensure LDAP client certificate is created
ensure_ldap_client_certificate:
  k8s.certmanager_certificate_present:
    - name: ldap-client-cert
    - certificate_name: ldap-test-client-cert
    - namespace: {{ pillar['ldap']['namespace'] }}
    - secret_name: ldap-client-tls
    - issuer_name: ldap-client-certs
    - issuer_kind: Issuer
    - common_name: ldap-test-client
    - duration: 8760h
    - renew_before: 720h

# Ensure LDAP connection spec is created
ensure_ldap_config_connect_spec:
  ldap.connect_spec_present:
    - name: ldap_config_connection_setup
    - spec_name: ldap_config_connection
    - connection_dict:
        url: {{ "ldap://" ~ pillar['ldap']['cert']['common_name'] }}
        bind:
          dn: {{ "cn=" ~ pillar['ldap']['admin-user']['name'] ~ "," ~ "cn=config" }}
          password: {{ pillar['ldap']['admin-user']['password'] }}
          method: simple
        tls:
          cacertfile: /tmp/ca.pem
          cert_manager_secret: ldap-client-tls
          namespace: {{ pillar['ldap']['namespace'] }}
          starttls: True
    - require:
      - file: ensure_config_ca_cert_file
