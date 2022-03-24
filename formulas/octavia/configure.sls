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

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

# octavia-db-manage --config-file /etc/octavia/octavia.conf upgrade head:
#   cmd.run:
#     - runas: octavia
#     - require:
#       - file: conf-files
#     - unless:
#       - fun: grains.equals
#         key: build_phase
#         value: configure

# octavia-db-manage --config-file /etc/octavia/octavia.conf upgrade_persistence:
#   cmd.run:
#     - runas: octavia
#     - require:
#       - file: conf-files
#     - unless:
#       - fun: grains.equals
#         key: build_phase
#         value: configure

mk_octavia_mgmt_network:
  cmd.script:
    - source: salt://formulas/octavia/files/mk_lb_mgmt_net.sh
    - template: jinja
    - defaults:
        octavia_password: {{ pillar['octavia']['octavia_service_password'] }}
        keystone_internal_endpoint: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        octavia_mgmt_subnet: {{ pillar['networking']['ocatvia']['octavia_mgmt_subnet'] }}
        octavia_mgmt_subnet_start: {{ pillar['networking']['ocatvia']['octavia_mgmt_subnet_start'] }}
        octavia_mgmt_subnet_end: {{ pillar['networking']['ocatvia']['octavia_mgmt_subnet_end'] }}
        octavia_mgmt_port_ip: {{ pillar['networking']['ocatvia']['octavia_mgmt_port_ip'] }}
    - require:
      - service: octavia_api_service
    - retry:
        attempts: 3
        interval: 10
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
    - makedirs: True
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='octavia', database='octavia') }}
        sql_persistence_connection_string: {{ constructor.mysql_url_constructor(user='octavia', database='octavia-persistence') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        controller_ip_port_list: {{ octavia_healthmon_url_constructor() }}
        octavia_password: {{ pillar['octavia']['octavia_service_password'] }}
        listen_api: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}:9001
        octavia_public_endpoint: {{ constructor.endpoint_url_constructor(project='octavia', service='octavia', endpoint='public') }}
    - names:
      - /etc/octavia/octavia.conf:
        - source: salt://formulas/octavia/files/octavia.conf
      # - /etc/octavia/policy.yaml:
      #   - source: salt://formulas/octavia/files/policy.yaml

# octavia_api_service:
#   service.running:
#     - name: octavia-api
#     - enable: True
#     - watch:
#       - file: conf-files