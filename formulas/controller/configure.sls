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
    - makedirs: True
    - require:
      - /kvm

/kvm/vms:
  file.directory:
    - makedirs: True
    - require:
      - /kvm

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

#Vendor compresses fcos images
  {% if args['name'] == 'fcore40' %}
unzip_{{ args ['name'] }}:
  cmd.run:
    - name: zcat /kvm/images/{{ os }}.original > /kvm/images/{{ os }}
    - name: mv /kvm/images/{{ os }} /kvm/images/{{ os }}.original
    - creates:
      - /kvm/images/{{ os }}.original
  {% endif %}

set_format_{{ os }}:
  cmd.run:
    - cwd: /kvm/images
    - name: qemu-img convert -O raw {{ os }}.original {{ os }}.raw
    - creates:
      - /kvm/images/{{ os }}.raw

  {% endif %}

 {% if args['name'] == 'fcore40' %}
/kvm/images/{{ os }}-latest:
  file.symlink:
    - target: /kvm/images/{{ os }}.raw
    - force: True
 {% else %}
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
 {% endif %}
{% endfor %}

haveged_service:
  service.running:
    - name: haveged
    - enable: true
