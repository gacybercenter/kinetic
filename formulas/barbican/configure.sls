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

/etc/barbican/barbican.conf:
  file.managed:
    - source: salt://formulas/barbican/files/barbican.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='barbican', database='barbican') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['barbican']['barbican_service_password'] }}
        kek: {{ pillar['barbican']['simplecrypto_key'] }}

{% if grains['os_family'] == 'RedHat' %}
/etc/httpd/conf.d/wsgi-barbican.conf:
  file.managed:
    - source: salt://formulas/barbican/files/wsgi-barbican.conf
{% endif %}

barbican_keystone_listener_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: barbican-keystone-listener
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-barbican-keystone-listener
{% endif %}
    - enable: True
    - watch:
      - file: /etc/barbican/barbican.conf

barbican_worker_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: barbican-worker
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-barbican-worker
{% endif %}
    - enable: True
    - watch:
      - file: /etc/barbican/barbican.conf

barbican_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: httpd
{% endif %}
    - enable: true
    - watch:
      - file: /etc/barbican/barbican.conf
{% if grains['os_family'] == 'RedHat' %}
      - file: /etc/httpd/conf.d/wsgi-barbican.conf
{% endif %}
