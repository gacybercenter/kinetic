include:
  - /formulas/common/ldapadmin/install


{% set ldap_spec = pillar.get('ldap', {}).get('spec_name', 'default') %}
{% set base_dn = pillar.get('ldap', {}).get('base_dn') %}
{% set ou_groups = pillar.get('ldap', {}).get('ou_groups', 'ou=groups') %}
{% set ou_users = pillar.get('ldap', {}).get('ou_users', 'ou=users') %}

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

{% for group, data in pillar.get('ldap', {}).get('groups', {}).items() %}
  {% set project_name = group %}
  {% set project_description = "Project for " ~ group %}
openstack_project_{{ group }}:
  kinetic-openstack.project_present:
    - name: {{ project_name }}
    - description: {{ project_description }}
    - enabled: True
    - cloud: rsc
  {% if 'roles' in data %}
    {% for role in data.get('roles', []) %}
openstack_role_assignment_{{ group }}_{{ role }}:
  kinetic-openstack.role_assignment_present:
    - role_name: {{ role }}
    - project_name: {{ project_name }}
    - group_name: {{ group }}
    - cloud: rsc
    - require:
      - kinetic-openstack: openstack_project_{{ group }}
    {% endfor %}
  {% endif %}

ldap_project_group_{{ group }}:
  ldap_utils.update_group:
    - spec_name: {{ ldap_spec }}
    - group_dn: "cn={{ group }},{{ ou_groups }},{{ base_dn }}"
    - cn: {{ group }}
    - description: "LDAP group for {{ group }} OpenStack project members"
    - members:
        {% for member in data.get('members', []) %}
        - "cn={{ member }},{{ ou_users }},{{ base_dn }}"
        {% endfor %}
    - require:
      - sls: /formulas/common/ldapadmin/install
      - ldap: ensure_ldap_connect_spec

ldap_admin_group_{{ group }}:
  ldap_utils.update_group:
    - spec_name: {{ ldap_spec }}
    - group_dn: "cn=admin-{{ group }},{{ ou_groups }},{{ base_dn }}"
    - cn: admin-{{ group }}
    - description: "LDAP admins for {{ group }} OpenStack project"
    - members: []
    - require:
      - ldap_utils: ldap_project_group_{{ group }}
      - sls: /formulas/common/ldapadmin/install
      - ldap: ensure_ldap_connect_spec

{% endfor %}
