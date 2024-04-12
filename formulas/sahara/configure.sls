## Copyright 2019 Augusta University
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
  - /formulas/common/fluentd/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

sahara-db-manage --config-file /etc/sahara/sahara.conf upgrade head:
  cmd.run:
    - runas: sahara
    - require:
      - file: /etc/sahara/sahara.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/sahara/sahara.conf:
  file.managed:
    - source: salt://formulas/sahara/files/sahara.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='sahara', database='sahara') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['sahara']['sahara_service_password'] }}
        host: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

sahara_api_service:
  service.running:
    - name: apache2
    - enable: True
    - watch:
      - file: /etc/sahara/sahara.conf

sahara_engine_service:
  service.running:
    - name: sahara-engine
    - enable: True
    - watch:
      - file: /etc/sahara/sahara.conf
