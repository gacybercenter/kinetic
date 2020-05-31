include:
  - /formulas/cache/install
  - /formulas/common/base
  - /formulas/common/networking

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
        d /run/apt-cacher-ng 0755 apt-cacher-ng apt-cacher-ng
{% endif %}

/etc/apt-cacher-ng/acng.conf:
  file.managed:
    - source: salt://formulas/cache/files/acng.conf

curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/etc/apt-cacher-ng/centos_mirrors:
  cmd.run:
    - creates: /etc/apt-cacher-ng/centos_mirrors
    - require:
      - file: /etc/apt-cacher-ng/acng.conf

apt-cacher-ng_service:
  service.running:
    - name: apt-cacher-ng
    - enable: True
    - watch:
      - file: /etc/apt-cacher-ng/acng.conf
{% if grains['os_family'] == 'RedHat' %}
      - file: /etc/tmpfiles.d/apt-cacher-ng.conf
{% endif %}

/var/www/html/images:
  file.directory

{% for os, args in pillar.get('images', {}).items() %}
create_{{ args['name'] }}:
  cmd.run:
    - name: virt-builder --install cloud-init --output {{ os }}.raw {{ args['name'] }}
    - cwd: /var/www/html/images
    - creates: /var/www/html/images/{{ os }}.raw
    - require:
      - file: /var/www/html/images
{% endfor %}

sha512sum * > checksums:
  cmd.run:
    - cwd: /var/www/html/images
    - onchanges:
      - archive: extract_*
