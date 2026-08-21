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

{% set type = grains['type'] %}

{% if 'raid' in pillar['hosts'][type]['kvm_disk_config']['type'] %}
{% set raid_level = pillar['hosts'][type]['kvm_disk_config']['type'].split('raid') %}

kvm_array:
  raid.present:
    - name: /dev/md/kvm_array
    - level: {{ raid_level[1] }}
    - devices:
  {% for device in pillar['hosts'][type]['kvm_disk_config']['members'] %}
      - {{ device }}
  {% endfor %}
    - chunk: 512
    - run: true

pv_config:
  lvm.pv_present:
    - name: /dev/md/kvm_array
    - require:
      - kvm_array

vg_config:
  lvm.vg_present:
    - name: kvm_vg
    - devices:
      - /dev/md/kvm_array
    - require:
      - pv_config

lv_config:
  lvm.lv_present:
    - name: kvm_lv
    - vgname: kvm_vg
    - extents: 100%FREE
    - require:
      - vg_config

fs:
  cmd.run:
    - name: mkfs.xfs -K /dev/mapper/kvm_vg-kvm_lv
    - unless:
      - salt-call disk.fstype /dev/mapper/kvm_vg-kvm_lv | grep -qn xfs
    - require:
      - lv_config

/kvm:
  mount.mounted:
    - device: /dev/mapper/kvm_vg-kvm_lv
    - fstype: xfs
    - mkmnt: true
    - require:
      - fs

{% elif 'standard' in pillar['hosts'][type]['kvm_disk_config']['type'] %}
{% set target_device = pillar['hosts'][type]['kvm_disk_config']['members'][0] %}
  {% if target_device == "rootfs" %}

/kvm:
  file.directory

  {% else %}

pv_config:
  lvm.pv_present:
    - name: {{ target_device }}

vg_config:
  lvm.vg_present:
    - name: kvm_vg
    - devices:
      - {{ target_device }}
    - require:
      - pv_config

lv_config:
  lvm.lv_present:
    - name: kvm_lv
    - vgname: kvm_vg
    - extents: 100%FREE
    - require:
      - vg_config

fs:
  cmd.run:
    - name: mkfs.xfs -K /dev/mapper/kvm_vg-kvm_lv
    - unless:
      - salt-call disk.fstype /dev/mapper/kvm_vg-kvm_lv | grep -qn xfs
    - require:
      - lv_config

/kvm:
  mount.mounted:
    - device: /dev/mapper/kvm_vg-kvm_lv
    - fstype: xfs
    - mkmnt: true
    - require:
      - fs

  {% endif %}
{% endif %}

/kvm/images:
  file.directory:
    - user: libvirt-qemu
    - group: kvm
    - makedirs: True
    - require:
      - /kvm

/kvm/vms:
  file.directory:
    - user: libvirt-qemu
    - group: kvm
    - makedirs: True
    - require:
      - /kvm


# Define the libvirt storage pool
define_vms_pool:
  virt.pool_defined:
    - name: vms
    - ptype: dir
    - target: /kvm/vms
    - autostart: True
    - require:
      - file: /kvm/vms
    - unless: virsh pool-list |grep vms

# New: Manage AppArmor profile for libvirt-qemu
apparmor_libvirt_dir:
  file.directory:
    - name: /etc/apparmor.d/abstractions/libvirt-qemu.d
    - user: root
    - group: root
    - mkdirs: True
    - dir_mode: 755
    - file_mode: 644

apparmor_libvirt_profile:
  file.managed:
    - name: /etc/apparmor.d/abstractions/libvirt-qemu.d/kvm_vms
    - contents: |
        /kvm/vms/** rwk,
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: apparmor_libvirt_dir
    - watch_in:
      - service: apparmor_service

apparmor_service:
  service.running:
    - name: apparmor
    - enable: True
    - watch:
      - file: apparmor_libvirt_profile
apparmor_pkg:
  pkg.installed:
    - name: apparmor
{% for os, args in pillar.get('images', {}).items() %}
  {% if args['type'] == 'virt-builder' %}
create_{{ args['name'] }}:
  cmd.run:
    - name: virt-builder --smp 4 -m 4096 --selinux-relabel --install cloud-init,cloud-utils-growpart --uninstall firewalld --output {{ os }}.raw {{ args['name'] }}
    - cwd: /kvm/images
    - creates: /kvm/images/{{ os }}.raw
    - require:
      - file: /kvm/images

  {% elif args['type'] == 'url' %}
create_{{ args['name'] }}:
  file.managed:
    - name: /kvm/images/{{ os }}.original
    - source: {{ args['url'] }}
    - skip_verify: True

set_format_{{ os }}:
  cmd.run:
    - cwd: /kvm/images
    - name: qemu-img convert -O raw {{ os }}.original {{ os }}.raw
    - creates:
      - /kvm/images/{{ os }}.raw

  {% endif %}
sysprep_{{ args['name'] }}:
  cmd.run:
    - name: virt-sysprep -a {{ os }}.raw --truncate /etc/machine-id
    - cwd: /kvm/images
    - onchanges:
      - create_{{ args['name'] }}

/kvm/images/{{ os }}-latest:
  file.symlink:
    - target: /kvm/images/{{ os }}.raw
    - force: True
    - require:
      - cmd: sysprep_{{ args['name'] }}
{% endfor %}

haveged_service:
  service.running:
    - name: haveged
    - enable: true

libvirt_control_key:
  ssh_auth.present:
    - user: ubuntu
    - names:
      - {{ pillar['hosts']['controller']['ssh_cert'] }}
    - enc: {{ pillar['hosts']['controller']['ssh_enc'] }}

## add libvirt control key
#ssh_libvirt_key:
#  file.managed:
#    - name: /home/ubuntu/.ssh/id_ed25519
#    - user: ubuntu
#    - group: ubuntu
#    - mode: 600
#    - attrs: a
#    - contents_pillar: hosts:controller:ssh_key
