include:
  - /formulas/pxe/install

apache2_service:
  service.running:
    - name: apache2

https://github.com/ipxe/ipxe.git:
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

php7.3_module:
  apache_module.enabled:
    - name: php7.3

/var/www/html/index.html:
  file.absent

/var/www/html/index.php:
  file.managed:
    - source: salt://formulas/pxe/files/index.php

/var/www/html/preseed.pxe:
  file.managed:
    - source: salt://formulas/pxe/files/preseed.pxe

/var/www/html/kickstart.pxe:
  file.managed:
    - source: salt://formulas/pxe/files/kickstart.pxe

/var/www/html/assignments:
  file.directory

{% for type in pillar['hosts'] %}
  {% if 'ubuntu' in pillar['hosts'][type]['os'] %}
/var/www/html/preseed/{{ type }}.preseed:
  file.managed:
    - source: salt://formulas/pxe/files/common.preseed
    - makedirs: True
    - template: jinja
    - defaults:
        proxy: {{ pillar['hosts'][type]['proxy'] }}
        root_password_crypted: {{ pillar['hosts'][type]['root_password_crypted'] }}
        zone: {{ pillar['timezone'] }}
        ntp_server: {{ pillar['hosts'][type]['ntp_server'] }}
        disk: {{ pillar['hosts'][type]['disk'] }}
        interface: {{ pillar['hosts'][type]['interface'] }}
    {% if pillar['hosts'][type]['proxy'] == 'pull_from_mine' %}
    - context:
      {% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
      {% if cache_addresses_dict == {} %}
        proxy: ""
      {% else %}
        {% for host in cache_addresses_dict %}
        proxy: http://{{ cache_addresses_dict[host][0] }}:3142
        {% endfor %}
      {% endif %}
    {% endif %}
  {% elif 'centos' in pillar['hosts'][type]['os'] %}
/var/www/html/kickstart/{{ type }}.kickstart:
  file.managed:
    - source: salt://formulas/pxe/files/common.kickstart
    - makedirs: True
    - template: jinja
    - defaults:
        proxy: {{ pillar['hosts'][type]['proxy'] }}
        root_password_crypted: {{ pillar['hosts'][type]['root_password_crypted'] }}
        zone: {{ pillar['timezone'] }}
        ntp_server: {{ pillar['hosts'][type]['ntp_server'] }}
        disk: {{ pillar['hosts'][type]['disk'] }}
        interface: {{ pillar['hosts'][type]['interface'] }}
    {% if pillar['hosts'][type]['proxy'] == 'pull_from_mine' %}
    - context:
      {% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
      {% if cache_addresses_dict == {} %}
        proxy: ""
      {% else %}
        {% for host in cache_addresses_dict %}
        proxy: http://{{ cache_addresses_dict[host][0] }}:3142
        {% endfor %}
      {% endif %}
    {% endif %}
  {% endif %}
{% endfor %}
