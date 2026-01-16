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
          dn: {{ "cn=" ~ pillar['ldap']['admin-user']['name'] ~ "," ~ "cn=config" }}
          password: {{ pillar['ldap']['admin-user']['password'] }}
          method: simple
        tls:
          cacertfile: /tmp/ca.pem
          starttls: True
    - require:
      - file: ensure_config_ca_cert_file

# Ensure Modules are loaded
{% for index, module in pillar['ldap']['modules'] | enumerate %}
ensure_ldap_module_{{ module['name'] }}:
  ldap.module_present:
    - name: ldap_module_setup_{{ module['name'] }}
    - spec_name: ldap_config_connection
    - module_base_dn: "cn=module{{ '{' }}{{ index }}{{ '}' }},cn=config"
    - modules:
        - {{ module }}
    - module_path: {{ pillar['ldap']['modulePath'] }}
    - require:
      - ldap: ensure_ldap_config_connect_spec
      
ensure_ldap_overlay_{{ module['name'] }}:
  ldap.auditlog_overlay_present:
    - name: ldap_{{ module['name'] }}
    - spec_name: ldap_config_connection
    - database_dn: "olcDatabase={2}hdb,cn=config"
    - logfile: {{ pillar['ldap']['logfile'] }}
    - require:
      - ldap: ensure_ldap_config_connect_spec
      - ldap: ensure_ldap_module_{{ module['name'] }}
{% endfor %}
