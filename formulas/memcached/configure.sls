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
  - /formulas/common/fluentd/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

{% if grains['os_family'] == 'Debian' %}

memcached_config:
  file.managed:
    - name: /etc/memcached.conf
    - source: salt://formulas/memcached/files/memcached.conf
    - template: jinja
    - defaults:
        listen_addr: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

{% elif grains['os_family'] == 'RedHat' %}

memcached_config:
  file.managed:
    - name: /etc/sysconfig/memcached
    - source: salt://formulas/memcached/files/memcached
    - template: jinja
    - defaults:
        listen_addr: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

{% endif %}

## This is necessary because the upstream mcd unit file has a race condition where the network interface
## may not fully be up when src=dhcp prior to memcached starting when network.target is the prereq.
## network-online.target ensure that there is an address available
## ref: https://unix.stackexchange.com/questions/157529/how-to-force-network-target-to-wait-for-dhcp-with-systemd-networkd
memcached_unit_file_update:
  file.line:
    - name: /usr/lib/systemd/system/memcached.service
    - content: After=network-online.target
    - match: After=network.target
    - mode: replace

systemctl daemon-reload:
  cmd.run:
    - onchanges:
      - file: memcached_unit_file_update

memcached_service_check:
  service.running:
    - name: memcached
    - enable: True
    - watch:
      - file: memcached_config
    - require:
      - file: memcached_unit_file_update
