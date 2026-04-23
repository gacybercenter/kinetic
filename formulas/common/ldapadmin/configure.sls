include:
  - /formulas/common/ldapadmin/install


{% set ldap_spec = pillar.get('ldap', {}).get('spec_name', 'default') %}
{% set base_dn = pillar['ldap']['values']['global']['ldapDomain'] %}

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
        - "{{ member }}"
        {% endfor %}
        {% else %}
        - "admin"
        {% endif %}
    - require:
      - ldap: ensure_ldap_connect_spec

openstack_role_assignment_{{ group }}_{{ role }}:
  kinetic-openstack.role_assignment_present:
    - role_name: member
    - project_name: {{ project_name }}
    - group_name: {{ group }}
    - group_domain: ldap
    - project_domain: Default
    - cloud: rsc
    - require:
      - kinetic-openstack: openstack_project_{{ group }}
    {% endfor %}
  {% endif %}

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
        - "{{ member }}"
        {% endfor %}
        {% else %}
        - "admin"
        {% endif %}
    - require:
      - ldap: ldap_project_group_{{ group }}
      - ldap: ensure_ldap_connect_spec

openstack_role_assignment_{{ group }}_admin:
  kinetic-openstack.role_assignment_present:
    - role_name: admin
    - project_name: {{ project_name }}
    - group_name: {{ group }}
    - group_domain: ldap
    - project_domain: Default
    - cloud: rsc
    - require:
      - kinetic-openstack: openstack_project_{{ group }}
    {% endfor %}


  {% endif %}
{% endif %}

{% endfor %}
