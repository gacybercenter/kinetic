include:
  - /formulas/memcached/install
  - formulas/common/base
  - formulas/common/networking

/etc/memcached.conf:
  file.managed:
    - source: salt://apps/memcached/files/memcached.conf
    - source_hash: salt://apps/memcached/files/hash
    - template: jinja
    - defaults:
        listen_addr: {{ grains['ipv4'][0] }}

memcached_service_check:
  service.running:
    - name: memcached
    - enable: True
    - watch:
      - file: /etc/memcached.conf
