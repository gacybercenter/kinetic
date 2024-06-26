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

barbican-manage db upgrade:
  cmd.run:
    - runas: barbican
    - require:
      - file: /etc/barbican/barbican.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

conf-files:
  file.managed:
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='barbican', database='barbican') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['barbican']['barbican_service_password'] }}
        kek: {{ pillar['barbican']['simplecrypto_key'] }}
    - names:
      - /etc/barbican/barbican.conf:
        - source: salt://formulas/barbican/files/barbican.conf

barbican_keystone_listener_service:
  service.running:
    - name: barbican-keystone-listener
    - enable: True
    - watch:
      - file: conf-files

barbican_worker_service:
  service.running:
    - name: barbican-worker
    - enable: True
    - watch:
      - file: conf-files

barbican_service:
  service.running:
    - name: apache2
    - enable: true
    - watch:
      - file: conf-files
