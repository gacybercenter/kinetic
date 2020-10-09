include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

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
