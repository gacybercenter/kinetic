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

cinder-manage db sync:
  cmd.run:
    - runas: cinder
    - require:
      - file: /etc/cinder/cinder.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% if pillar['cephconf']['autoscale'] == 'off' %}
set_volumes_pool_pgs:
  event.send:
    - name: set/volume/pool_pgs
    - data:
        pgs: {{ pillar['cephconf']['volumes_pgs'] }}
{% endif %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/cinder/cinder.conf:
  file.managed:
    - source: salt://formulas/cinder/files/cinder.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='cinder', database='cinder') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['cinder']['cinder_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ constructor.endpoint_url_constructor(project='glance', service='glance', endpoint='public') }}
        rbd_secret_uuid: {{ pillar['ceph']['volumes-uuid'] }}
{% if salt['pillar.get']('hosts:barbican:enabled', 'False') == True %}
        barbican_endpoint: {{ constructor.endpoint_url_constructor(project='barbican', service='barican', endpoint='internal') }}
{% endif %}

cinder_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-cinder-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf

cinder_scheduler_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: cinder-scheduler
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-cinder-scheduler
{% endif %}
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf
