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
  - /formulas/common/fluentd/fluentd

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

magnum-db-manage upgrade:
  cmd.run:
    - runas: magnum
    - require:
      - file: /etc/magnum/magnum.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}


/etc/magnum/magnum.conf:
  file.managed:
    - source: salt://formulas/magnum/files/magnum.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='magnum', database='magnum') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['magnum']['magnum_service_password'] }}
        host: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

magnum_conductor_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: magnum-conductor
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-magnum-conductor
{% endif %}
    - enable: True
    - watch:
      - file: /etc/magnum/magnum.conf

magnum_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: magnum-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-magnum-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/magnum/magnum.conf
