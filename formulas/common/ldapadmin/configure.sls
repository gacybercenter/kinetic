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
        url: {{ "ldap://" ~ pillar['ldap']['cert']['commonname'] }}
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

{% for group, data in pillar.get('ldap', {}).get('groups', {}).items() %}
{% set project_name = group %}
{% set project_description = "Project for " ~ group %}

openstack_project_{{ group }}:
  kinetic_openstack.project_present:
    - name: {{ project_name }}
    - description: {{ project_description }}
    - enabled: True
    - cloud: rsc

{% if group != 'admins' %}
ldap_project_group_{{ group }}:
  ldap.group_present:
    - name: ldap_project_group_{{ group }}
    - spec_name: {{ ldap_spec }}
    - base_dn: "ou=groups,{{ base_dn }}"
    - cn: {{ group }}
    - description: "LDAP group for {{ group }} OpenStack project members"
    - members:
        {% if data.get('members', [])|length > 0 %}
        {% for member in data.get('members', []) %}
        {% if '=' in member %}
        - "{{ member }}"
        {% else %}
        - "cn={{ member }},{{ users_ou }},{{ base_dn }}"
        {% endif %}
        {% endfor %}
        {% else %}
        - "cn=admin,{{ users_ou }},{{ base_dn }}"
        {% endif %}
    - require:
      - ldap: ensure_ldap_connect_spec

openstack_role_assignment_{{ group }}_member:
  kinetic_openstack.role_assignment_present:
    - role_name: member
    - project_name: {{ project_name }}
    - group_name: {{ group }}
    - group_domain: ldap
    - project_domain: Default
    - cloud: rsc
    - require:
      - kinetic_openstack: openstack_project_{{ group }}

{% endif %}

{% if group != 'admins' %}
ldap_admin_group_{{ group }}:
  ldap.group_present:
    - name: ldap_admin_group_{{ group }}
    - spec_name: {{ ldap_spec }}
    - base_dn: "ou=groups,{{ base_dn }}"
    - cn: admin-{{ group }}
    - description: "LDAP admins for {{ group }} OpenStack project"
    - members:
        {% if data.get('admin_members', [])|length > 0 %}
        {% for member in data.get('admin_members', []) %}
        {% if '=' in member %}
        - "{{ member }}"
        {% else %}
        - "cn={{ member }},{{ users_ou }},{{ base_dn }}"
        {% endif %}
        {% endfor %}
        {% else %}
        - "cn=admin,{{ users_ou }},{{ base_dn }}"
        {% endif %}
    - require:
      - ldap: ldap_project_group_{{ group }}
      - ldap: ensure_ldap_connect_spec

openstack_role_assignment_{{ group }}_admin:
  kinetic_openstack.role_assignment_present:
    - role_name: admin
    - project_name: {{ project_name }}
    - group_name: {{ group }}
    - group_domain: ldap
    - project_domain: Default
    - cloud: rsc
    - require:
      - kinetic_openstack: openstack_project_{{ group }}

{% endif %}

{% endfor %}
