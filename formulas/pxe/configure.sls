include:
  - /formulas/pxe/install

https://git.ipxe.org/ipxe.git:
  git.latest:
    - target: /var/www/html/ipxe
    - require:
      - sls: /formulas/pxe/install

/var/www/html/ipxe/src/kinetic.ipxe:
  file.managed:
    - source: salt://formulas/pxe/files/kinetic.ipxe

create_efi_module:
  cmd.run:
    - name: |
        make bin-x86_64-efi/ipxe.efi EMBED=kinetic.ipxe && cp bin-x86_64-efi/ipxe.efi /srv/tftp/
    - cwd: /var/www/html/ipxe/src/
    - creates: /srv/tftp/ipxe.efi

php7.0_module:
  apache_module.enabled:
    - name: php7.0

/var/www/html/index.html:
  file.absent

/var/www/html/hosts:
  file.managed:
    - contents: |
      {% for type, macs in salt['pillar.get']('hosts', {}).items() %}
        {% for mac in pillar['hosts'][type]['macs'] %}
          {{ mac }} = {{ type }}
        {%- endfor %}
      {% endfor %}

/var/www/html/index.php:
  file.managed:
    - source: salt://formulas/pxe/files/index.php

/var/www/html/cache.pxe:
  file.managed:
    - source: salt://formulas/pxe/files/cache.pxe

{% for type in pillar['hosts'] %}
/var/www/html/preseed/{{ type }}.preseed:
  file.managed:
    - source: salt://formulas/pxe/files/common.preseed
    - template: jina
    - defaults:
#        proxy: {{ pillar['hosts'][type]['proxy'] }}
        root-password-crypted: {{ pillar['hosts'][type]['root-password-crypted'] }}
        zone: {{ pillar['hosts'][type]['zone'] }}
        ntp-server: {{ pillar['hosts'][type]['ntp-server'] }}
        disk: {{ pillar['hosts'][type]['disk'] }}
{% endfor %}

/var/www/html/preseed/cache2.preseed:
  file.managed:
    - source: salt://formulas/pxe/files/cache.preseed
    - makedirs: True
    - template: jinja
