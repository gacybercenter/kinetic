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
    - source: {{ args['remote_url'] }}
    - source_hash: {{ args['remote_hash'] }}
    - source_hash_name: {{ args['remote_source_hash_name'] }}
    - makedirs: True

{% if {{ args['needs_conversion'] }} = true %}
qemu-img convert -f qcow2 {{ args['name'] }} {{ os }}.raw:
  cmd.run:
    - cwd: /var/www/html/images
    - creates: /var/www/html/images/{{ os }}.raw
{% endif %}

{% endfor %}
