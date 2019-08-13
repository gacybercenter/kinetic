include:
  - /formulas/cache/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/apt-cacher-ng/acng.conf:
  file.managed:
    - source: salt://formulas/cache/files/acng.conf

apt-cacher-ng_service:
  service.running:
    - name: apt-cacher-ng
    - watch:
      - file: /etc/apt-cacher-ng/acng.conf

{% for os, args in pillar.get('images', {}).items() %}
extract_{{ args['name'] }}:
  archive.extracted:
    - name: /var/www/html/images
    - source: {{ args['remote_url'] }}
    - source_hash: {{ args['remote_hash'] }}
    - makedirs: true
{% endfor %}

sha512sum * > checksums:
  cmd.run:
    - cwd: /var/www/html/images
    - onchanges: 
      - archive: extract_*

mine.update:
  module.run:
    - network.interfaces: []
  event.send:
    - name: cache/mine/address/update
    - data: "Cache mine has been updated."
