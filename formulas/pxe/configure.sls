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
      {% for type, macs in salt['pillar.get']('hosts', {}).iteritems() %}
        {{ pillar[type]['macs'][loop.index0] }} = {{ type }}
      {% endfor %}
/var/www/html/index.php:
  file.managed:
    - source: salt://formulas/pxe/files/index.php
