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

{% if grains['os_family'] == 'RedHat' %}
/etc/tmpfiles.d/apt-cacher-ng.conf:
  file.managed:
    - contents: |
        d /run/apt-cacher-ng 0755 apt-cacher-ng apt=cacher-ng
{% endif %}

/etc/apt-cacher-ng/acng.conf:
  file.managed:
    - source: salt://formulas/cache/files/acng.conf

curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/etc/apt-cacher-ng/centos_mirrors:
  cmd.run:
    - creates: /etc/apt-cacher-ng/centos_mirrors
    - require:
      - file: /etc/apt-cacher-ng/acng.conf

/var/run/apt-cacher-ng:
  file.directory:
    - user: apt-cacher-ng
    - group: apt-cacher-ng

apt-cacher-ng_service:
  service.running:
    - name: apt-cacher-ng
    - watch:
      - file: /etc/apt-cacher-ng/acng.conf
      - file: /var/run/apt-cacher-ng

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
