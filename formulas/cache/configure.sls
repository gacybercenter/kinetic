include:
  - /formulas/cache/install

/etc/apt-cacher-ng/acng.conf:
  file.managed:
    - source: salt://formulas/cache/files/acng.conf

apt-cacher-ng_service:
  service.running:
    - name: apt-cacher-ng
    - watch:
      - file: /etc/apt-cacher-ng/acng.conf

{% for os, args in pillar.get('images', {}).items() %}
/var/www/html/images/{{ args['name'] }}:
  file.managed:
    - source: {{ args['url'] }}
    - source_hash: {{ args['hash'] }}
    - source_hash_name: {{ args['source_hash_name'] }}
    - makedirs: True
{% endfor %}
