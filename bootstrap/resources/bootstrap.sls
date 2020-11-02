## Copyright 2020 Augusta University
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

bootstrap_packages:
  pkg.installed:
    - pkgs:
      - qemu-kvm
      - genisoimage
      - python3-libvirt
      - libguestfs-tools
    - reload_modules: true
    - onchanges_in:
      - pkg: update_packages_bootstrap

{% if grains['os_family'] == 'Debian' %}

bootstrap_packages_deb:
  pkg.installed:
    - pkgs:
      - libvirt-clients
      - libvirt-daemon-system
      - qemu-utils
    - reload_modules: true
    - onchanges_in:
      - pkg: update_packages_bootstrap

{% elif grains['os_family'] == 'RedHat' %}

bootstrap_packages_rpm:
  pkg.installed:
    - pkgs:
      - libvirt-client
      - libvirt-daemon-kvm
    - reload_modules: true
    - onchanges_in:
      - pkg: update_packages_bootstrap
    - onchanges_in:
      - pkg: update_packages_bootstrap

{% endif %}

update_packages_bootstrap:
  pkg.uptodate:
    - refresh: rue
    - dist_upgrade: True

/kvm/images:
  file.directory:
    - makedirs: True

/kvm/vms:
  file.directory:
    - makedirs: True

## <hack> the kmod state doesn't correctly parse arguments like the kmod module
## does. Shoule open a PR to fix it, but this works for now
/etc/modules-load.d/nested_kvm.conf:
  file.managed:
    - contents: |
{% if "AMD" in grains['cpu_model'] %}
        kvm_amd nested=1
{% elif "Intel" in grains['cpu_model'] %}
        kvm_intel nested=1
{% endif %}

load_kvm:
  cmd.run:
{% if "AMD" in grains['cpu_model'] %}
    - name: rmmod kvm_amd ; modprobe kvm_amd nested=1
{% elif "Intel" in grains['cpu_model'] %}
    - name: rmmod kvm_intel ; modprobe kvm_intel nested=1
{% endif %}
    - onchanges:
      - file: /etc/modules-load.d/nested_kvm.conf
## </hack>

## images
debian_base_image:
  file.managed:
    - name: /kvm/images/debian10.raw
    - source: https://cdimage.debian.org/cdimage/openstack/current-10/debian-10-openstack-amd64.raw
    - source_hash: https://cdimage.debian.org/cdimage/openstack/current-10/SHA512SUMS

{% for host in ['salt, pxe'] %}
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




salt_image:
  file.copy:
    - source: /kvm/images/debian10.raw
    - target: /kvm/vms/salt/disk0.raw

salt_image_resize:
  cmd.run:
    - name: qemu-img resize -f raw /kvm/vms/salt/disk0.raw 16G
    - onchanges:
      - file: salt_image

/kvm/vms/salt/config.xml:
  file.managed:

pxe_image:
  file.copy:
    - source: /kvm/images/debian10.raw
    - target: /kvm/vms/pxe/disk0.raw

pxe_image_resize:
  cmd.run:
    - name: qemu-img resize -f raw /kvm/vms/pxe/disk0.raw 16G
    - onchanges:
      - file: pxe_image