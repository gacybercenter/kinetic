## Copyright 2018 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/common/fluentd/fluentd

/etc/salt/minion.d/mine_functions.conf:
  file.managed:
    - contents: |
        mine_functions:
          redfish.gather_endpoints:
            - {{ pillar ['networking']['subnets']['oob'] }}
            - {{ pillar ['api_user'] }}
            - {{ pillar ['bmc_password'] }}

/var/www/html/assignments:
  file.directory

/var/www/html/index.html:
  file.absent

https://github.com/ipxe/ipxe.git:
  git.latest:
    - target: /var/www/html/ipxe
    - user: root
    - require:
      - sls: /formulas/pxe/install

conf-files:
  file.managed:
    - template: jinja
    - defaults:
        pxe_record: {{ pillar['pxe']['record'] }}
        pxe_name: {{ pillar['pxe']['name'] }}
    - names:
      - /var/www/html/ipxe/src/kinetic.ipxe:
        - source: salt://formulas/pxe/files/kinetic.ipxe
      - /etc/apache2/sites-available/wsgi.conf:
        - source: salt://formulas/pxe/files/wsgi.conf
      - /etc/apache2/sites-available/tftp.conf:
        - source: salt://formulas/pxe/files/tftp.conf
      - /etc/apache2/conf-available/tftp.conf:
        - source: salt://formulas/pxe/files/tftp.conf
      - /etc/apache2/apache2.conf:
        - source: salt://formulas/pxe/files/apache2.conf
      - /var/www/html/index.py:
        - source: salt://formulas/pxe/files/index.py

create_efi_module:
  cmd.run:
    - name: |
        make bin-x86_64-efi/ipxe.efi EMBED=kinetic.ipxe
    - cwd: /var/www/html/ipxe/src/
    - creates: /var/www/html/ipxe/src/bin-x86_64-efi/ipxe.efi

Disable default site:
  apache_site.disabled:
    - name: 000-default

wsgi_site:
  apache_site.enabled:
    - name: wsgi

wsgi_module:
  apache_module.enabled:
    - name: wsgi

{% for type in pillar['hosts'] if salt['pillar.get']('hosts:'+type+':style') == 'physical' %}
/var/www/html/configs/{{ type }}:
  file.managed:
  {% if salt['pillar.get']('hosts:'+type+':style') == 'container' %}
    - source: salt://formulas/pxe/files/container.preseed
  {% elif 'ubuntu' in pillar['hosts'][type]['os'] %}
    - source: salt://formulas/pxe/files/common.preseed
  {% elif 'centos' in pillar['hosts'][type]['os'] %}
    - source: salt://formulas/pxe/files/common.kickstart
  {% endif %}
    - makedirs: True
    - template: jinja
    - defaults:
        proxy: {{ pillar['hosts'][type]['proxy'] }}
        root_password_crypted: {{ pillar['hosts'][type]['root_password_crypted'] }}
        zone: {{ pillar['timezone'] }}
        ntp_server: {{ pillar['hosts'][type]['ntp_server'] }}
        disk: {{ pillar['hosts'][type]['disk'] }}
        interface: {{ pillar['hosts'][type]['interface'] }}
        master_record: {{ pillar['salt']['record'] }}
        salt_version: stable {{ salt['pillar.get']('salt:version', 'latest') }}
  {% if pillar['hosts'][type]['proxy'] == 'pull_from_mine' %}
    - context:
    {% if salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length == 0 %}
        proxy: ""
    {% else %}
      ##pick a random cache and iterate through its addresses, choosing only the management address
      {% for address in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last () %}
        {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        proxy: http://{{ address }}:3142
        {% endif %}
      {% endfor %}
    {% endif %}
  {% endif %}
{% endfor %}

tftp_dirs:
  file.directory:
    - names:
      - /srv/tftp/jammy
      - /srv/tftp/assignments

tftp_site:
  apache_site.enabled:
    - name: tftp

tftp_conf:
  apache_conf.enabled:
    - name: tftp

/srv/tftp/jammy/ubuntu2204.iso:
  file.managed:
    - makedirs: True
    - source: https://cdimage.ubuntu.com/ubuntu-server/jammy/daily-live/current/jammy-live-server-amd64.iso
    - source_hash: https://cdimage.ubuntu.com/ubuntu-server/jammy/daily-live/current/SHA256SUMS

/srv/tftp/jammy/vmlinuz:
  file.absent

/srv/tftp/jammy/initrd:
  file.absent

mount_iso:
  mount.mounted:
    - name: /srv/tftp/jammy/ubuntu2204.iso
    - device: /mnt
    - fstype: iso9660
    - mkmnt: True
    - require:
      - file: /srv/tftp/jammy/ubuntu2204.iso
      - file: /srv/tftp/jammy/vmlinuz
      - file: /srv/tftp/jammy/initrd

copy_vmlinuz:
  file.copy:
    - name: /mnt/casper/vmlinuz
    - dest: /srv/tftp/jammy/vmlinuz
    - require:
      - mount: mount_iso

copy_initrd:
  file.copy:
    - name: /mnt/casper/initrd
    - dest: /srv/tftp/jammy/initrd
    - require:
      - mount: mount_iso

umount_iso:
  mount.unmounted:
    - name: /mnt
    - require:
      - mount: mount_iso
      - file: copy_vmlinuz
      - file: copy_initrd

apache2_service:
  service.running:
    - name: apache2
    - watch:
      - apache_module: wsgi_module
      - file: /etc/apache2/sites-available/wsgi.conf
      - file: /etc/apache2/sites-available/tftp.conf
      - file: /etc/apache2/apache2.conf
      - apache_site: tftp
      - apache_site: wsgi
      - apache_site: 000-default

build_phase_final:
  grains.present:
    - name: build_phase
    - value: configure

salt-minion_mine_watch:
  cmd.run:
    - name: 'salt-call service.restart salt-minion'
    - bg: True
    - onchanges:
      - file: /etc/salt/minion.d/mine_functions.conf
    - order: last
