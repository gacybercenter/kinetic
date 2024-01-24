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

https://github.com/ipxe/ipxe.git:
  git.latest:
    - target: /var/www/html/ipxe
    - user: root
    - require:
      - sls: /formulas/pxe/install
    - unless:
      - ls /var/www/html/ipxe/src | grep -q kinetic.ipxe

conf-files:
  file.managed:
    - template: jinja
    - defaults:
        pxe_record: {{ pillar['pxe']['record'] }}
        pxe_name: {{ pillar['pxe']['name'] }}
        private: {{ salt['network.convert_cidr'](pillar['networking']['subnets']['private'])['network'] }}
        private_netmask: {{ salt['network.convert_cidr'](pillar['networking']['subnets']['private'])['netmask'] }}
        private_range: {{ pillar['networking']['subnets']['private']|replace('0/24', '') }}
        sfe: {{ salt['network.convert_cidr'](pillar['networking']['subnets']['sfe'])['network'] }}
        sfe_netmask: {{ salt['network.convert_cidr'](pillar['networking']['subnets']['sfe'])['netmask'] }}
        sfe_range: {{ pillar['networking']['subnets']['sfe']|replace('0/24', '') }}
        sbe: {{ salt['network.convert_cidr'](pillar['networking']['subnets']['sbe'])['network'] }}
        sbe_netmask: {{ salt['network.convert_cidr'](pillar['networking']['subnets']['sbe'])['netmask'] }}
        sbe_range: {{ pillar['networking']['subnets']['sbe']|replace('0/24', '') }}
        mgmt: {{ pillar['networking']['subnets']['management'].split('/')[0] }}
        mgmt_start: {{ pillar['dhcp-options']['mgmt_start'] }}
        mgmt_end: {{ pillar['dhcp-options']['mgmt_end'] }}
        mgmt_gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
        mgmt_netmask: {{ pillar['dhcp-options']['mgmt_netmask'] }}
        mgmt_dns: {{ pillar['dhcp-options']['mgmt_dns'] }}
        domain: {{ pillar['dhcp-options']['domain'] }}
        tftp: {{ pillar['dhcp-options']['tftp'] }}
        arm_efi: {{ pillar['dhcp-options']['arm_efi'] }}
        x86_efi: {{ pillar['dhcp-options']['x86_efi'] }}
        omapi_port: {{ pillar['omapi.server_port'] }}
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
      - /etc/dhcp/dhcpd.conf:
        - source: salt://formulas/pxe/files/dhcpd.conf

create_x86_64_efi_module:
  cmd.run:
    - name: |
        make bin-x86_64-efi/ipxe.efi EMBED=kinetic.ipxe
    - cwd: /var/www/html/ipxe/src/
    - creates: /var/www/html/ipxe/src/bin-x86_64-efi/ipxe.efi

copy_x86_64_efi_module:
  file.copy:
      - makedirs: True
      - names:
        - /var/www/html/{{ pillar['dhcp-options']['x86_efi'] }}:
          - source: /var/www/html/ipxe/src/bin-x86_64-efi/ipxe.efi
        - /srv/tftp/{{ pillar['dhcp-options']['x86_efi'] }}:
          - source: /var/www/html/ipxe/src/bin-x86_64-efi/ipxe.efi
      - require:
        - cmd: create_x86_64_efi_module

create_aarch64_efi_module:
  cmd.run:
    - name: |
        make bin-arm64-efi/ipxe.efi CROSS=aarch64-linux-gnu- EMBED=kinetic.ipxe
    - cwd: /var/www/html/ipxe/src/
    - creates: /var/www/html/ipxe/src/bin-arm64-efi/ipxe.efi

copy_aarch64_efi_module:
  file.copy:
      - makedirs: True
      - names:
        - /var/www/html/{{ pillar['dhcp-options']['arm_efi'] }}:
          - source: /var/www/html/ipxe/src/bin-arm64-efi/ipxe.efi
        - /srv/tftp/{{ pillar['dhcp-options']['arm_efi'] }}:
          - source: /var/www/html/ipxe/src/bin-arm64-efi/ipxe.efi
      - require:
        - cmd: create_aarch64_efi_module

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

/srv/tftp/jammy/ubuntu2204-amd64.iso:
  file.managed:
    - makedirs: True
    - source: https://cdimage.ubuntu.com/releases/jammy/release/inteliot/ubuntu-22.04-live-server-amd64+intel-iot.iso
    - source_hash: https://cdimage.ubuntu.com/releases/jammy/release/inteliot/SHA256SUMS

/srv/tftp/jammy/ubuntu2204-arm64.iso:
  file.managed:
    - makedirs: True
    - source: https://cdimage.ubuntu.com/releases/jammy/release/ubuntu-22.04.3-live-server-arm64.iso
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
    - name: isc-dhcp-server
    - watch:
      - file: /etc/dhcp/dhcpd.conf

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
