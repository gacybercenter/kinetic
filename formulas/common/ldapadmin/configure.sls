include:
  - /formulas/common/ldapadmin/install

# Provision OpenStack projects based on LDAP groups from pillar data
{% for group, data in pillar.get('ldap', {}).get('groups', {}).items() %}
  {% set project_name = group %}
  {% set project_description = "Project for " ~ group %}
openstack_project_{{ group }}:
  openstack.project_present:
    - name: {{ project_name }}
    - description: {{ project_description }}
    - enabled: True
    - auth_args: {{ pillar.get('openstack', {}).get('cloud_name', 'rsc-admin') }}
  {% if 'roles' in data %}
    {% for role in data.get('roles', []) %}
openstack_role_assignment_{{ group }}_{{ role }}:
  openstack.role_assignment_present:
    - role_name: {{ role }}
    - project_name: {{ project_name }}
    - group_name: {{ group }}
    - auth_args: {{ pillar.get('openstack', {}).get('cloud_name', 'rsc-admin') }}
    - require:
      - openstack: openstack_project_{{ group }}
    {% endfor %}
  {% endif %}
{% endfor %}
