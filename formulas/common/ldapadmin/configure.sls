include:
  - /formulas/common/ldapadmin/install


{% set ldap_spec = pillar.get('ldap', {}).get('spec_name', 'default') %}
{% set base_dn = pillar['ldap']['values']['global']['ldapDomain'] %}
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
  {% do salt.log.debug("Using base_dn: " ~ base_dn) %}
  {% do salt.log.debug("Using ou_groups: " ~ ou_groups) %}
  {% do salt.log.debug("Constructed group DN: cn=" ~ group ~ "," ~ ou_groups ~ "," ~ base_dn) %}
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

{% if group != 'admins' %}
ldap_project_group_{{ group }}:
  ldap.group_present:
    - name: ldap_project_group_{{ group }}
    - spec_name: {{ ldap_spec }}
    - base_dn: "{{ ou_groups }},{{ base_dn }}"
    - cn: {{ group }}
    - description: "LDAP group for {{ group }} OpenStack project members"
    - members:
        {% if data.get('members', [])|length > 0 %}
        {% for member in data.get('members', []) %}
        - "{{ member }}"
        {% endfor %}
        {% else %}
        - "admin"
        {% endif %}
    - require:
      - ldap: ensure_ldap_connect_spec
{% endif %}

{% if group != 'admins' %}
ldap_admin_group_{{ group }}:
  ldap.group_present:
    - name: ldap_admin_group_{{ group }}
    - spec_name: {{ ldap_spec }}
    - base_dn: "{{ ou_groups }},{{ base_dn }}"
    - cn: admin-{{ group }}
    - description: "LDAP admins for {{ group }} OpenStack project"
    - members:
        {% if data.get('admin_members', [])|length > 0 %}
        {% for member in data.get('admin_members', []) %}
        - "{{ member }}"
        {% endfor %}
        {% else %}
        - "admin"
        {% endif %}
    - require:
      - ldap: ldap_project_group_{{ group }}
      - ldap: ensure_ldap_connect_spec
{% endif %}

{% endfor %}
