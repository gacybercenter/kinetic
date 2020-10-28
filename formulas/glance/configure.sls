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
  - /formulas/common/ceph/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

glance-manage db_sync:
  cmd.run:
    - runas: glance
    - require:
      - file: /etc/glance/glance-api.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/ceph/ceph.client.images.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-images-keyring
    - mode: 640
    - user: root
    - group: glance

/etc/sudoers.d/ceph:
  file.managed:
    - contents:
      - ceph ALL = (root) NOPASSWD:ALL
      - Defaults:ceph !requiretty
    - mode: 644

/etc/glance/glance-api.conf:
  file.managed:
    - source: salt://formulas/glance/files/glance-api.conf
    - template: jinja
    - defaults:
        sql_connection_string: {{ constructor.mysql_url_constructor(user='glance', database='glance') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['glance']['glance_service_password'] }}

glance_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: glance-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-glance-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/glance/glance-api.conf
