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
  - /formulas/common/ceph/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/ceph/ceph.client.volumes.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-volumes-keyring
    - mode: "0640"
    - user: root
    - group: cinder

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
        api_servers: {{ constructor.endpoint_url_constructor(project='glance', service='glance', endpoint='internal') }}
        rbd_secret_uuid: {{ pillar['ceph']['volumes-uuid'] }}


## Somehow, the cinder service is attempted to be started before cinder.conf
## is fully configured, leading to a situation where it tries to run with a deafult
## configuration, which does not work and dies when it tries to write to the nonexisten
## sqlite database.  A single retry generally resolves the issue
## This can be removed once universal retries are implemented
cinder_volume_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: cinder-volume
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-cinder-volume
{% endif %}
    - enable: true
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - watch:
      - file: /etc/cinder/cinder.conf
