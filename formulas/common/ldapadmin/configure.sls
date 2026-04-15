include:
  - /formulas/common/ldapadmin/install

# Provision OpenStack projects based on LDAP groups from pillar data
# Debug information for troubleshooting
debug_pillar_data:
  test.nop:
    - name: Debug Pillar Data
    - comment: |
        Debugging Pillar Data for LDAP Groups:
        Pillar Keys: {{ pillar.keys()|join(', ') }}
        LDAP in Pillar: {{ 'ldap' in pillar }}
        {% if 'ldap' in pillar %}
        LDAP Groups in Pillar: {{ 'groups' in pillar['ldap'] }}
        {% if 'groups' in pillar['ldap'] %}
        Groups: {{ pillar['ldap']['groups'].keys()|join(', ') }}
        {% endif %}
        {% endif %}

  {% for group, data in pillar.get('ldap', {}).get('groups', {}).items() %}
    {% if 'openstack_project' in data %}
      {% set project_name = data['openstack_project']['name'] %}
      {% set project_description = data['openstack_project'].get('description', 'Project for ' ~ group) %}
debug_group_{{ group }}:
  test.nop:
    - name: Debug Group {{ group }}
    - comment: |
        Processing Group: {{ group }}
        Project Name: {{ project_name }}
        Project Description: {{ project_description }}
        Roles: {{ data['openstack_project'].get('roles', [])|join(', ') }}

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
