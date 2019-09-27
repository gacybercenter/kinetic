include:
  - /formulas/memcached/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/memcached.conf:
  file.managed:
    - source: salt://formulas/memcached/files/memcached.conf
    - template: jinja
    - defaults:
        listen_addr: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

memcached_service_check:
  service.running:
    - name: memcached
    - enable: True
    - watch:
      - file: /etc/memcached.conf
