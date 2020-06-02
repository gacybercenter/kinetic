include:
  - /formulas/memcached/install
  - /formulas/common/base
  - /formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

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

memcached_unit_file_update:
  file.line:
    - name: /usr/lib/systemd/system/memcached.service
    - content: After=network-online.target
    - match: After=network.target
    - mode: replace

memcached_service_check:
  service.running:
    - name: memcached
    - enable: True
    - watch:
      - file: memcached_config
