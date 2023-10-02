## Copyright 2018 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/common/fluentd/fluentd

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['os_family'] == 'Debian' %}
  {% set webserver = 'apache2' %}
{% elif grains['os_family'] == 'RedHat' %}
  {% set webserver = 'httpd' %}
{% endif %}

{% if grains['spawning'] == 0 %}
  {% set keystone_conf = pillar['openstack_services']['keystone']['configuration']['services']['keystone']['endpoints'] %}

init_keystone:
  cmd.run:
    - name: |
        keystone-manage db_sync
        keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
        keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
        keystone-manage bootstrap --bootstrap-password {{ pillar['openstack']['admin_password'] }} \
  {%- for endpoint, attribs in keystone_conf.items() %}
        --bootstrap-{{ endpoint }}-url {{ attribs['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ attribs['port'] }}{{ attribs['path'] }} \
  {%- endfor %}
        --bootstrap-region-id RegionOne
    - require:
      - file: /etc/keystone/keystone.conf
      - file: /etc/openstack/clouds.yml
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

service_project_init:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack project create service --domain default --description "Service Project"
    - require:
      - file: /etc/openstack/clouds.yml
      - cmd: init_keystone
    - unless:
      - export OS_CLOUD=kinetic && openstack project list | awk '{ print $4 }' | grep -q service

user_role_init:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role create user
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack role list | awk '{ print $4 }' | grep -q user

  {% for project in pillar['openstack_services'] %}
    {% if salt['pillar.get']('hosts:'+project+':enabled', False) == True %}
{{ project }}_user_init:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack user create --domain default --password {{ pillar [project][project+'_service_password'] }} {{ project }}
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack user list | awk '{ print $4 }' | grep -q {{ project }}

{{ project }}_user_role_grant:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role add --project service --user {{ project }} admin
    - require:
      - cmd: {{ project }}_user_init
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack role assignment list | grep $(openstack role list | grep admin | awk '{print $2}') | grep $(openstack project list | grep service | awk '{print $2}') | grep -q $(openstack user list | grep {{ project }} | awk '{print $2}')

      {% for service, attribs in pillar['openstack_services'][project]['configuration']['services'].items() %}
{{ service }}_service_create:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack service create --name {{ service }} --description "{{ attribs['description'] }}" {{ attribs['type'] }}
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack service list | awk '{ print $4 }' | grep -q {{ service }}

        {% for endpoint, params in attribs['endpoints'].items() %}

{{ service }}_{{ endpoint }}_endpoint_create:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack endpoint create --region RegionOne {{ attribs['type'] }} {{ endpoint }} '{{ constructor.endpoint_url_constructor(project, service, endpoint) }}'
    - require:
      - cmd: {{ service }}_service_create
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack endpoint list | awk '{ print $6,$12 }' | grep -q "{{ service }} {{ endpoint }}"
        {% endfor %}
      {% endfor %}
    {% endif %}
  {% endfor %}

##LDAP-specific changes
  {% if salt['pillar.get']('keystone:ldap_enabled', False) == True %}
create_ldap_domain:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack domain create --description "LDAP Domain" {{ pillar['keystone']['ldap_configuration']['keystone_domain'] }}
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack domain list | awk '{ print $4 }' | grep -q {{ pillar['keystone']['ldap_configuration']['keystone_domain'] }}
  {% endif %}

## barbican-specific changes
  {% if salt['pillar.get']('hosts:barbican:enabled', False) == True %}
creator_role_init:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role create creator
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack role list | awk '{ print $4 }' | grep -q creator

creator_role_assignment:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role add --project service --user barbican creator
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack role assignment list | grep $(openstack role list | grep creator | awk '{print $2}') | grep $(openstack project list | grep service | awk '{print $2}') | grep -q $(openstack user list | grep barbican | awk '{print $2}')

  {% endif %}

  {% if salt['pillar.get']('hosts:heat:enabled', True) == True %}
## heat-specific configurations
create_heat_domain:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack domain create --description "Heat stack projects and users" heat
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack domain list | awk '{ print $4 }' | grep -q heat

create_heat_admin_user:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack user create --domain heat --password {{ pillar ['heat']['heat_service_password'] }} heat_domain_admin
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack user list --domain heat | awk '{ print $4 }' | grep -q heat_domain_admin

heat_domain_admin_role_assignment:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role add --domain heat --user-domain heat --user heat_domain_admin admin
    - require:
      - file: /etc/openstack/clouds.yml

heat_stack_owner_role_init:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role create heat_stack_owner
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack role list | awk '{ print $4 }' | grep -q heat_stack_owner

heat_stack_user_role_init:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role create heat_stack_user
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack role list | awk '{ print $4 }' | grep -q heat_stack_user
  {% endif %}

## magnum-specific configurations
  {% if salt['pillar.get']('hosts:magnum:enabled', False) == True %}
create_magnum_domain:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack domain create --description "Owns users and projects created by magnum" magnum
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack domain list | awk '{ print $4 }' | grep -q magnum

create_magnum_admin_user:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack user create --domain magnum --password {{ pillar ['magnum']['magnum_service_password'] }} magnum_domain_admin
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack user list --domain magnum | awk '{ print $4 }' | grep -q magnum_domain_admin

magnum_domain_admin_role_assignment:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role add --domain magnum --user-domain magnum --user magnum_domain_admin admin
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack role assignment list | grep $(openstack role list | grep admin | awk '{print $2}') | grep $(openstack domain list | grep magnum | awk '{print $2}') | grep -q $(openstack user list | grep magnum_domain_admin | awk '{print $2}')

  {% endif %}

## zun-specific configurations
  {% if salt['pillar.get']('hosts:zun:enabled', False) == True %}
kuryr_user_init:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack user create --domain default --password {{ pillar ['zun']['kuryr_service_password'] }} kuryr
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack user list | awk '{ print $4 }' | grep -q kuryr

kuryr_user_role_grant:
  cmd.run:
    - name: export OS_CLOUD=kinetic && openstack role add --project service --user kuryr admin
    - require:
      - file: /etc/openstack/clouds.yml
    - unless:
      - export OS_CLOUD=kinetic && openstack role assignment list | grep $(openstack role list | grep admin | awk '{print $2}') | grep $(openstack project list | grep service | awk '{print $2}') | grep -q $(openstack user list | grep kuryr | awk '{print $2}')

  {% endif %}
{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

##LDAP-specific changes
{% if salt['pillar.get']('keystone:ldap_enabled', False) == True %}
keystone_domain_files:
  file.managed:
    - makedirs: True
    - template: jinja
    - defaults:
        ldap_url: {{ pillar ['common_ldap_configuration']['address'] }}
        ldap_user: {{ pillar ['common_ldap_configuration']['bind_user'] }}
        ldap_password: {{ pillar ['bind_password'] }}
        ldap_suffix: {{ pillar ['common_ldap_configuration']['base_dn'] }}
        user_tree_dn: {{ pillar ['common_ldap_configuration']['user_dn'] }}
        group_tree_dn: {{ pillar ['common_ldap_configuration']['group_dn'] }}
        user_filter: {{ pillar ['keystone']['ldap_configuration']['user_filter'] }}
        group_filter: {{ pillar ['keystone']['ldap_configuration']['group_filter'] }}
        sql_connection_string: {{ constructor.mysql_url_constructor('keystone', 'keystone') }}
        public_endpoint: {{ constructor.endpoint_url_constructor('keystone', 'keystone', 'public') }}
    - names:
      - /etc/keystone/domains/keystone.{{ pillar['keystone']['ldap_configuration']['keystone_domain'] }}.conf
        - source: salt://formulas/keystone/files/keystone-ldap.conf
      - /etc/keystone/ldap_ca.crt:
        - contents_pillar: ldap_ca
  {% if grains['os_family'] == 'Debian' %}
      - /usr/local/share/ca-certificates/ldap_ca.crt:
  {% elif grains['os_family'] == 'RedHat' %}
      - /etc/pki/ca-trust/source/anchors/ldap_ca.crt
  {% endif %}
        - contents_pillar: ldap_ca
    - require_in:
      - service: wsgi_service

update_certificate_store:
  cmd.run:
  {% if grains['os_family'] == 'Debian' %}
    - name: update-ca-certificates
  {% elif grains['os_family'] == 'RedHat' %}
    - name: update-ca-trust extract
  {% endif %}
    - onchanges:
      - file: keystone_domain_files
{% endif %}

/var/lib/keystone/keystone.db:
  file.absent

conf-files:
  file.managed:
    - makedirs: True
    - template: jinja
    - defaults:
        sql_connection_string: {{ constructor.mysql_url_constructor(user='keystone', database='keystone') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        public_endpoint: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public', base=True) }}
        token_expiration: {{ pillar['keystone']['token_expiration'] }}
        webserver: {{ webserver }}
        ServerName: ServerName {{ grains['id'] }}
        password: {{ pillar['openstack']['admin_password'] }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
    - names:
      - /etc/keystone/keystone.conf:
        - source: salt://formulas/keystone/files/keystone.conf
      - /etc/keystone/keystone.policy.yaml:
        - source: salt://formulas/keystone/files/keystone.policy.yaml
      - /etc/openstack/clouds.yml:
        - source: salt://formulas/common/openstack/files/clouds.yml
      {% if grains['os_family'] == 'Debian' %}
      - /etc/apache2/sites-available/keystone.conf:
        - source: salt://formulas/keystone/files/apache-keystone.conf
      - /etc/apache2/apache2.conf:
        - source: salt://formulas/keystone/files/apache2.conf
      {% elif grains['os_family'] == 'RedHat' %}
      - /etc/httpd/conf.d/keystone.conf:
        - source: salt://formulas/keystone/files/apache-keystone.conf
      - /etc/httpd/conf/httpd.conf:
        - source: salt://formulas/keystone/files/httpd.conf
      {% endif %}

fernet-keys:
  file.managed:
    - contents_pillar: keystone:fernet_primary
    - makedirs: True
    - mode: "0600"
    - user: keystone
    - group: keystone
    - names:
      - /etc/keystone/fernet-keys/0:
        - contents_pillar: keystone:fernet_primary
      - /etc/keystone/fernet-keys/1:
        - contents_pillar: keystone:fernet_secondary

wsgi_service:
  service.running:
    - name: {{ webserver }}
    - enable: True
    - init_delay: 10
    - watch:
      - file: conf-files
