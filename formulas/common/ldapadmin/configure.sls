include:
  - /formulas/common/ldapadmin/install

# Provision OpenStack projects based on LDAP groups from pillar data
{% if 'ldap' in pillar and 'groups' in pillar['ldap'] %}
  {% for group, data in pillar['ldap']['groups'].items() %}
    {% if 'openstack_project' in data %}
      {% set project_name = data['openstack_project']['name'] %}
      {% set project_description = data['openstack_project'].get('description', 'Project for ' ~ group) %}
openstack_project_{{ group }}:
  openstack.project_present:
    - name: {{ project_name }}
    - description: {{ project_description }}
    - enabled: True
    {% if 'roles' in data['openstack_project'] %}
      {% for role in data['openstack_project']['roles'] %}
openstack_role_assignment_{{ group }}_{{ role }}:
  openstack.role_assignment_present:
    - role_name: {{ role }}
    - project_name: {{ project_name }}
    - group_name: {{ group }}
    - require:
      - openstack: openstack_project_{{ group }}
      {% endfor %}
    {% endif %}
    {% endif %}
  {% endfor %}
{% endif %}
