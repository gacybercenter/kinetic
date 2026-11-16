## Copyright 2021 United States Army Cyber School
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

{% if grains['spawning'] == 0 %}

cyborg-dbsync --config-file /etc/cyborg/cyborg.conf upgrade:
  cmd.run:
    - runas: cyborg
    - require:
      - file: /etc/cyborg/cyborg.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/cyborg/cyborg.conf:
  file.managed:
    - source: salt://formulas/cyborg/files/cyborg.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='cyborg', database='cyborg') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        auth_strategy: auth_strategy = keystone
        auth_type: auth_type = password
        auth_version: auth_version = v3
        auth_protocol: auth_protocol = https
        password: {{ pillar['cyborg']['cyborg_service_password'] }}
        api: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}

/etc/cyborg/api-paste.ini:
  file.managed:
    - source: salt://formulas/cyborg/files/api-paste.ini
    - require:
      - sls: /formulas/cyborg/install

/etc/systemd/system/cyborg-api.service:
  file.managed:
    - source: salt://formulas/cyborg/files/cyborg-api.service
    - require:
      - sls: /formulas/cyborg/install

cyborg_api_service:
  service.running:
    - name: cyborg-api
    - enable: true
    - watch:
      - file: /etc/cyborg/cyborg.conf

/etc/systemd/system/cyborg-conductor.service:
  file.managed:
    - source: salt://formulas/cyborg/files/cyborg-conductor.service
    - require:
      - sls: /formulas/cyborg/install

cyborg_conductor_service:
  service.running:
    - name: cyborg-conductor
    - enable: true
    - watch:
      - file: /etc/cyborg/cyborg.conf
