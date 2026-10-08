# Implements: 800-171 3.5.8
# Optional OpenLDAP ppolicy (pwdInHistory) for LDAP-stored passwords.
# Keycloak LDAP federation for realm rsc is READ_ONLY, so realm
# passwordHistory(N) does not apply to directory users. Enable from
# kinetic-pillar; this state does not invent a history count.
#
# Does not replace the existing StartTLS bind used by prov.sls.

include:
  - /formulas/common/ldapadmin/prov

{% set ppolicy = pillar.get('ldap', {}).get('ppolicy', {}) %}
{% if ppolicy.get('enabled') %}
{% set suffix = pillar.get('ldap', {}).get('root_dn', {}).get('dn', 'dc=rsc,dc=gacyberrange,dc=org') %}
{% set policy_dn = ppolicy.get('policy_dn', 'cn=default,ou=policies,' ~ suffix) %}
{% set pwd_in_history = ppolicy.get('pwd_in_history') %}
{% set config_bind_dn = ppolicy.get('config_bind_dn', 'cn=admin,cn=config') %}

{% if pwd_in_history is none %}
ppolicy_pwd_in_history_required:
  test.fail_without_changes:
    - name: ldap:ppolicy:pwd_in_history must be set in kinetic-pillar when ppolicy is enabled
    - comment: Refuse to invent a password-history count
{% else %}

ensure_ppolicy_config_spec:
  ldap.connect_spec_present:
    - name: ldap_ppolicy_config_connection
    - spec_name: ldap_ppolicy_config
    - connection_dict:
        url: {{ "ldap://" ~ pillar['ldap']['cert']['commonname'] }}
        admin_bind:
          dn: {{ config_bind_dn }}
          password: {{ pillar['ldap']['admin-user']['password'] }}
          method: simple
        tls:
          cacertfile: /tmp/ca.pem
          starttls: True
    - require:
      - file: ensure_ca_cert_file

ensure_openldap_ppolicy:
  ldap.ppolicy_present:
    - name: openldap_ppolicy
    - spec_name: ldap_keycloak_connection
    - config_spec_name: ldap_ppolicy_config
    - suffix: {{ suffix }}
    - policy_dn: {{ policy_dn }}
    - pwd_in_history: {{ pwd_in_history }}
    - module_path: {{ ppolicy.get('module_path', pillar.get('ldap', {}).get('modulePath', '/opt/bitnami/openldap/lib/openldap')) }}
    - use_lockout: {{ ppolicy.get('use_lockout', True) }}
    - require:
      - ldap: ensure_ldap_connect_spec
      - ldap: ensure_ppolicy_config_spec
      - ldap: ensure_ldap_ous

{% endif %}
{% endif %}
