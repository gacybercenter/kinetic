include:
  - /formulas/common/ldapadmin/install


{% set ldap_spec = pillar.get('ldap', {}).get('spec_name', 'default') %}
{% set base_dn = pillar['ldap']['values']['global']['ldapDomain'] %}
{% set users_ou = pillar.get('ldap', {}).get('users_ou', 'ou=users') %}
{% set users_base_dn = users_ou ~ "," ~ base_dn %}

ensure_ca_cert_file:
  file.managed:
    - name: /tmp/ca.pem
    - contents: {{ pillar['ldap']['cert']['ca'] | json }}
    - mode: 644
    - user: root
    - group: root
    - makedirs: True

ensure_ldap_connect_spec:
  ldap.connect_spec_present:
    - name: ldap_connection_setup
    - spec_name: {{ ldap_spec }}
    - connection_dict:
        url: {{ "ldap://" ~ pillar['ldap']['cert']['common_name'] }}
        bind:
          dn: {{ "cn=" ~ pillar['ldap']['admin-user']['name'] ~ "," ~ base_dn }}
          password: {{ pillar['ldap']['admin-user']['password'] }}
          method: simple
        tls:
          cacertfile: /tmp/ca.pem
          starttls: True
    - require:
      - file: ensure_ca_cert_file

{% for user_id, user_data in pillar.get('ldap', {}).get('users', {}).items() %}

ldap_user_{{ user_id }}:
  ldap.user_present:
    - name: ldap_user_{{ user_id }}
    - spec_name: {{ ldap_spec }}
    - base_dn: "{{ users_base_dn }}"
    - uid: {{ user_data.get('uid', user_id) }}
    - cn: {{ user_data.get('name', user_id) }}
    - sn: {{ user_data.get('sn', '') }}
    - description: "LDAP user {{ user_data.get('name', user_id) }}"
    {% if user_data.get('pass') %}
    - password: {{ user_data['pass'] | json }}
    {% endif %}
    - require:
      - ldap: ensure_ldap_connect_spec

{% endfor %}
