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
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

service_project_init:
  keystone_project.present:
    - name: service
    - domain: default
    - description: Service Project

user_role_init:
  keystone_role.present:
    - name: user

{% for project in pillar['openstack_services'] %}

{{ project }}_user_init:
  keystone_user.present:
    - name: {{ project }}
    - domain: default
    - password: {{ pillar [project][project+'_service_password'] }}

{{ project }}_user_role_grant:
  keystone_role_grant.present:
    - name: admin
    - project: service
    - user: {{ project }}
    - require:
      - keystone_user: {{ project }}_user_init

  {% for service, attribs in pillar['openstack_services'][project]['configuration']['services'].items() %}

{{ service }}_service_create:
  keystone_service.present:
    - name: {{ service }}
    - type: {{ attribs['type'] }}
    - description: {{ attribs['description'] }}

    {% for endpoint, params in attribs['endpoints'].items() %}

{{ service }}_{{ endpoint }}_endpoint_create:
  keystone_endpoint.present:
    - name: {{ endpoint }}
    - url: {{ constructor.endpoint_url_constructor(project, service, endpoint) }}
    - region: RegionOne
    - service_name: {{ service }}
    - require:
      - keystone_service: {{ service }}_service_create

    {% endfor %}
  {% endfor %}
{% endfor %}

##LDAP-specific changes
{% if salt['pillar.get']('keystone:ldap_enabled', False) == True %}
create_ldap_domain:
  keystone_domain.present:
    - name: {{ pillar['keystone']['ldap_configuration']['keystone_domain'] }}
    - description: "LDAP Domain"

keystone_domain:
  file.managed:
    - name: /etc/keystone/domains/keystone.{{ pillar['keystone']['ldap_configuration']['keystone_domain'] }}.conf
    - source: salt://formulas/keystone/files/keystone-ldap.conf
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
    - require_in:
      - service: wsgi_service
      - cmd: init_keystone

{% endif %}

## barbican-specific changes
creator_role_init:
  keystone_role.present:
    - name: creator

creator_role_assignment:
  keystone_role_grant.present:
    - name: creator
    - project: service
    - user: barbican

## heat-specific configurations
create_heat_domain:
  keystone_domain.present:
    - name: heat
    - description: "Heat stack projects and users"

create_heat_admin_user:
  keystone_user.present:
    - name: heat_domain_admin
    - domain: heat
    - password: {{ pillar ['heat']['heat_service_password'] }}

heat_domain_admin_role_assignment:
  keystone_role_grant.present:
    - name: admin
    - domain: heat
    - user_domain: heat
    - user: heat_domain_admin

heat_stack_owner_role_init:
  keystone_role.present:
    - name: heat_stack_owner

heat_stack_user_role_init:
  keystone_role.present:
    - name: heat_stack_user

## magnum-specific configurations
create_magnum_domain:
  keystone_domain.present:
    - name: magnum
    - description: "Owns users and projects created by magnum"

create_magnum_admin_user:
  keystone_user.present:
    - name: magnum_domain_admin
    - domain: magnum
    - password: {{ pillar ['magnum']['magnum_service_password'] }}

## zun-specific configurations
kuryr_user_init:
  keystone_user.present:
    - name: kuryr
    - domain: default
    - password: {{ pillar ['zun']['kuryr_service_password'] }}

kuryr_user_role_grant:
  keystone_role_grant.present:
    - name: admin
    - project: service
    - user: kuryr

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/openstack/clouds.yml:
  file.managed:
    - source: salt://formulas/common/openstack/files/clouds.yml
    - makedirs: True
    - template: jinja
    - defaults:
        password: {{ pillar['openstack']['admin_password'] }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}

/var/lib/keystone/keystone.db:
  file.absent

/etc/keystone/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/keystone.conf
    - template: jinja
    - defaults:
        sql_connection_string: {{ constructor.mysql_url_constructor(user='keystone', database='keystone') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        public_endpoint: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public', base=True) }}
        token_expiration: {{ pillar['keystone']['token_expiration'] }}

keystone_site_configuration:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/apache2/sites-available/keystone.conf
{% elif grains['os_family'] == 'RedHat' %}
    - name: /etc/httpd/conf.d/keystone.conf
{% endif %}
    - source: salt://formulas/keystone/files/apache-keystone.conf
    - template: jinja
    - defaults:
        webserver: {{ webserver }}

webserver_conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/apache2/apache2.conf
    - source: salt://formulas/keystone/files/apache2.conf
{% elif grains['os_family'] == 'RedHat' %}
    - name: /etc/httpd/conf/httpd.conf
    - source: salt://formulas/keystone/files/httpd.conf
{% endif %}
    - template: jinja
    - defaults:
        ServerName: ServerName {{ grains['id'] }}

cert_bundle:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /usr/local/share/ca-certificates/ldap_ca.crt
{% elif grains['os_family'] == 'RedHat' %}
    - name: /etc/pki/ca-trust/source/anchors/ldap_ca.crt
{% endif %}
    - contents_pillar: ldap_ca

update_certificate_store:
  cmd.run:
{% if grains['os_family'] == 'Debian' %}
    - name: update-ca-certificates
{% elif grains['os_family'] == 'RedHat' %}
    - name: update-ca-trust extract
{% endif %}
    - onchanges:
      - file: cert_bundle

/etc/keystone/ldap_ca.crt:
  file.managed:
    - contents_pillar: ldap_ca

/etc/keystone/fernet-keys/0:
  file.managed:
    - contents_pillar: keystone:fernet_primary
    - makedirs: True
    - mode: 600
    - user: keystone
    - group: keystone

/etc/keystone/fernet-keys/1:
  file.managed:
    - contents_pillar: keystone:fernet_secondary
    - makedirs: True
    - mode: 600
    - user: keystone
    - group: keystone

json_policy_remove:
  file.absent:
    - name: /etc/keystone/policy.json

yaml_policy_apply:
  file.managed:
    - name: /etc/keystone/policy.yaml
{% if salt['pillar.get']('policies:keystone', '') != '' %}
    - contents_pillar: policies:keystone
{% else %}
    - contents: ''
{% endif %}

wsgi_service:
  service.running:
    - name: {{ webserver }}
    - enable: True
    - init_delay: 10
    - watch:
      - file: /etc/keystone/keystone.conf
      - file: webserver_conf
      - file: json_policy_remove
      - file: yaml_policy_apply
