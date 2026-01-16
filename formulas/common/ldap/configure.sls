include:
  - /formulas/common/ldap/install
  - formulas/common/ldap/prov

# Ensure Modules are loaded
ensure_ldap_modules:
  ldap.module_present:
    - name: ldap_module_setup
    - spec_name: ldap_keycloak_connection
    - module_base_dn: "cn=module{0},cn=config"
    - modules: {{ pillar['ldap']['modules'] }}
    - module_path: {{ pillar['ldap']['modulePath'] }}
    - require:
      - ldap: ensure_ldap_connect_spec

# # Ensure Auditlog Overlay is configured
# ensure_auditlog_overlay:
# ldap.auditlog_overlay_present:
#     - name: ldap_auditlog_setup
#     - spec_name: ldap_keycloak_connection
#     - database_dn: {{ pillar['ldap'].get('database_dn', 'olcDatabase={2}hdb,cn=config') }}
#     - logfile: {{ pillar['ldap'].get('logfile', '/audit.log') }}
#     - require:
#     - ldap: ensure_ldap_connect_spec
#     - ldap: ensure_ldap_root_dn
