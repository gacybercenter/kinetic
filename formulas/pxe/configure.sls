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
  - /formulas/common/fluentd/configure

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

ipxe_git:
  git.latest:
    - name: https://github.com/ipxe/ipxe.git
    - target: /var/www/html/ipxe
    - user: root
    - force_fetch: True
    - force_clone: True
    - require:
      - sls: /formulas/pxe/install
    - onchanges:
      - file: /var/www/html/ipxe/src/kinetic.ipxe

conf-files:
  file.managed:
    - template: jinja
    - makedirs: True
    - defaults:
        pxe_record: {{ pillar['pxe']['record'] }}
        pxe_name: {{ pillar['pxe']['name'] }}
        private: {{ pillar['networking']['subnets']['private'] }}
        private_range: {{ pillar['networking']['subnets']['private']|replace('0/24', '') }}
        sfe: {{ pillar['networking']['subnets']['sfe'] }}
        sfe_range: {{ pillar['networking']['subnets']['sfe']|replace('0/24', '') }}
        sbe: {{ pillar['networking']['subnets']['sbe'] }}
        sbe_range: {{ pillar['networking']['subnets']['sbe']|replace('0/24', '') }}
        mgmt: {{ pillar['networking']['subnets']['management'] }}
        mgmt_range: {{ pillar['networking']['subnets']['management']|replace('0/24', '') }}
        mgmt_gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
        dns: {{ pillar['dhcp-options']['dns'] }}
        domain: {{ pillar['dhcp-options']['domain'] }}
        tftp: {{ pillar['dhcp-options']['tftp'] }}
        arm_efi: {{ pillar['dhcp-options']['arm_efi'] }}
        x86_efi: {{ pillar['dhcp-options']['x86_efi'] }}
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
      - /etc/kea/kea-dhcp4.conf:
        - source: salt://formulas/pxe/files/dhcp4.json

create_x86_64_efi_module:
  cmd.run:
    - name: |
        rm -f /var/www/html/ipxe/src/bin-x86_64-efi/ipxe.efi && make bin-x86_64-efi/ipxe.efi EMBED=kinetic.ipxe
    - cwd: /var/www/html/ipxe/src/
    - require:
      - git: https://github.com/ipxe/ipxe.git
      - file: conf-files
    - onchanges:
      - file: /var/www/html/ipxe/src/kinetic.ipxe

copy_x86_64_efi_module:
  file.copy:
    - makedirs: True
    - force: True
    - names:
      - /var/www/html/{{ pillar['dhcp-options']['x86_efi'] }}:
        - source: /var/www/html/ipxe/src/bin-x86_64-efi/ipxe.efi
      - /srv/tftp/{{ pillar['dhcp-options']['x86_efi'] }}:
        - source: /var/www/html/ipxe/src/bin-x86_64-efi/ipxe.efi
    - require:
      - cmd: create_x86_64_efi_module
    - onchanges:
      - file: /var/www/html/ipxe/src/kinetic.ipxe

create_aarch64_efi_module:
  cmd.run:
    - name: |
        rm -f /var/www/html/ipxe/src/bin-arm64-efi/ipxe.efi && make bin-arm64-efi/ipxe.efi CROSS=aarch64-linux-gnu- EMBED=kinetic.ipxe
    - cwd: /var/www/html/ipxe/src/
    - require:
      - git: https://github.com/ipxe/ipxe.git
      - file: conf-files
    - onchanges:
      - file: /var/www/html/ipxe/src/kinetic.ipxe

copy_aarch64_efi_module:
  file.copy:
    - makedirs: True
    - force: True
    - names:
      - /var/www/html/{{ pillar['dhcp-options']['arm_efi'] }}:
        - source: /var/www/html/ipxe/src/bin-arm64-efi/ipxe.efi
      - /srv/tftp/{{ pillar['dhcp-options']['arm_efi'] }}:
        - source: /var/www/html/ipxe/src/bin-arm64-efi/ipxe.efi
    - require:
      - cmd: create_aarch64_efi_module
    - onchanges:
      - file: /var/www/html/ipxe/src/kinetic.ipxe

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

/srv/tftp/jammy/ubuntu2204-amd64.iso:
  file.managed:
    - makedirs: True
    - source: https://cdimage.ubuntu.com/releases/jammy/release/ubuntu-22.04.5-live-server-arm64.iso
    - source_hash: https://cdimage.ubuntu.com/releases/jammy/release/SHA256SUMS

/srv/tftp/jammy/ubuntu2204-arm64.iso:
  file.managed:
    - makedirs: True
    - source: https://cdimage.ubuntu.com/releases/jammy/release/ubuntu-22.04.5-live-server-arm64.iso
    - source_hash: https://cdimage.ubuntu.com/releases/jammy/release/SHA256SUMS

clean_dir:
  file.directory:
    - name: /srv/tftp/jammy/
    - clean: True
    - exclude_pat: "*.iso"
    - onchanges:
      - file: /srv/tftp/jammy/ubuntu2204-amd64.iso
      - file: /srv/tftp/jammy/ubuntu2204-arm64.iso

kernel_extract:
  cmd.script:
    - source: salt://formulas/pxe/files/kernel-extract.sh
    - cwd: /srv/tftp/jammy/
    - creates:
      - /srv/tftp/jammy/amd64/vmlinuz
      - /srv/tftp/jammy/amd64/initrd
      - /srv/tftp/jammy/arm64/vmlinuz
      - /srv/tftp/jammy/arm64/initrd
    - require:
      - file: /srv/tftp/jammy/ubuntu2204-amd64.iso
      - file: /srv/tftp/jammy/ubuntu2204-arm64.iso
      - file: clean_dir
    - onchanges:
      - file: /srv/tftp/jammy/ubuntu2204-amd64.iso
      - file: /srv/tftp/jammy/ubuntu2204-arm64.iso

apache2_service:
  service.running:
    - name: apache2
    - enable: True
    - watch:
      - apache_module: wsgi_module
      - file: /etc/apache2/sites-available/wsgi.conf
      - file: /etc/apache2/sites-available/tftp.conf
      - file: /etc/apache2/apache2.conf
      - file: /var/www/html/index.py
      - apache_site: tftp
      - apache_site: wsgi
      - apache_site: 000-default

dhcp_service:
  service.running:
    - name: kea-dhcp4-server
    - enable: True
    - watch:
      - file: /etc/kea/kea-dhcp4.conf

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
