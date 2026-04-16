include:
  - /formulas/common/ldapadmin/install

# Provision OpenStack projects based on LDAP groups from pillar data
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
{% endfor %}
