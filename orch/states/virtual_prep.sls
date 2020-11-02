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

{% set hostname = pillar['hostname'] %}
{% set type = hostname.split('-')[0] %}

/kvm/vms/{{ hostname }}/config.xml:
  file.managed:
    - source: salt://formulas/controller/files/common.xml
    - makedirs: True
    - template: jinja
    - defaults:
        name: {{ hostname }}
        ram: {{ pillar['hosts'][type]['ram'] }}
        cpu: {{ pillar['hosts'][type]['cpu'] }}
        networks: |
        {% for network, attribs in pillar['hosts'][type]['networks'].items() %}
        {% set slot = attribs['interfaces'][0].split('ens')[1] %}
          <interface type='bridge'>
            <source bridge='{{ network }}_br'/>
            <model type='virtio'/>
            <mac address='{{ salt['generate.mac']('52:54:00') }}'/>
            <address type='pci' domain='0x0000' bus='0x00' slot='0x{{ slot }}' function='0x0'/>
          </interface>
        {% endfor %}
        {% if grains['os_family'] == 'Debian' %}
        seclabel: <seclabel type='dynamic' model='apparmor' relabel='yes'/>
        {% elif grains['os_family'] == 'RedHat' %}
        seclabel: <seclabel type='dynamic' model='selinux' relabel='yes'/>
        {% endif %}

/kvm/vms/{{ hostname }}/disk0.raw:
  file.copy:
    - source: /kvm/images/{{ pillar['hosts'][type]['os'] }}-latest

qemu-img resize -f raw /kvm/vms/{{ hostname }}/disk0.raw {{ pillar['hosts'][type]['disk'] }}:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/disk0.raw

/kvm/vms/{{ hostname }}/data/meta-data:
  file.managed:
    - source: salt://formulas/controller/files/common.metadata
    - makedirs: True
    - template: jinja
    - defaults:
        hostname: {{ hostname }}

/kvm/vms/{{ hostname }}/data/user-data:
  file.managed:
    - source: salt://formulas/controller/files/common.userdata
    - makedirs: True
    - template: jinja
    - defaults:
        hostname: {{ hostname }}
        master_record: {{ pillar['salt']['record'] }}

genisoimage -o /kvm/vms/{{ hostname }}/config.iso -V cidata -r -J /kvm/vms/{{ hostname }}/data/meta-data /kvm/vms/{{ hostname }}/data/user-data:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/data/meta-data
      - /kvm/vms/{{ hostname }}/data/user-data

virsh create /kvm/vms/{{ hostname }}/config.xml:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/config.xml
