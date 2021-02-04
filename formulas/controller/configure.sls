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

{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

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

/kvm/glance_images:
  file.directory:
    - makedirs: True
    - require:
      - /kvm

/kvm/glance_templates:
  file.directory:
    - makedirs: True
    - require:
      - /kvm

/kvm/controller_images:
  file.directory:
    - makedirs: True
    - require:
      - /kvm

/kvm/controller_templates:
  file.directory:
    - makedirs: True
    - require:
      - /kvm

{% if grains['os_family'] == 'RedHat' %}
libvirtd_service:
  service.running:
    - name: libvirtd
    - enable: true
{% endif %}

{% for os, args in pillar.get('controller_images', {}).items() %}
/kvm/controller_templates/{{ args['image_name'] }}.yaml:
  file.managed:
    - template: jinja
    - contents: |
        image_name: {{ args.get('image_name', '') }}
        method: {{ args.get('method', '') }}
        image_url: {{ args.get('image_url', '') }}
        image_size: {{ args.get('size', '')}}
        conversion: {{ args.get('conversion', '') }}
        input_format: {{ args.get('input_format', '') }}
        output_format: {{ args.get('output_format', '') }}
        packages: {{ args.get('packages', '') }}
        customization: |
            {{ args.get('customization', '') | indent(12) }}

create_controller_image_{{ args['image_name'] }}:
  cmd.run:
    - name: 'python3 /tmp/image_bakery/image_bake.py -t /kvm/controller_templates/{{ args['image_name']}}.yaml -o /kvm/controller_images'
    - onchanges: [ /kvm/controller_templates/{{ args['image_name'] }}.yaml ]

/kvm/images/{{ os }}-latest:
  file.symlink:
    - target: /kvm/controller_images/{{ os }}
    - force: True
{% endfor %}

haveged_service:
  service.running:
    - name: haveged
    - enable: true

{% for address in salt['mine.get']('role:glance', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last () if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management'])%}

{% for os, args in pillar.get('glance_images', {}).items() %}
  
/kvm/glance_templates/{{ args['image_name'] }}.yaml:
  file.managed:
    - template: jinja
    - contents: |
        image_name: {{ args.get('image_name', '') }}
        method: {{ args.get('method', '') }}
        image_url: {{ args.get('image_url', '') }}
        image_size: {{ args.get('size', '') }}
        conversion: {{ args.get('conversion', '') }}
        input_format: {{ args.get('input_format', '') }}
        output_format: {{ args.get('output_format', '') }}
        packages: {{ args.get('packages', '') }}
        customization: |
            {{ args.get('customization', '') | indent(12) }}

create_glance_image_{{ args['image_name'] }}:
  cmd.run:
    - name: 'python3 /tmp/image_bakery/image_bake.py -t /kvm/glance_templates/{{ args['image_name']}}.yaml -o /kvm/glance_images'
    - onchanges: [ /kvm/glance_templates/{{ args['image_name'] }}.yaml ]

echo {{ address }}:
  cmd.run

upload_glance_image_{{ args['image_name'] }}:
  glance_image.present:
    - name: {{ args.get('image_name') }}
    - onchanges: [ /kvm/glance_templates/{{ args['image_name'] }}.yaml ]
    - filename: '/kvm/glance_images/{{ args.get('image_name') }}'
    - image_format: {{ args.get('output_format') }}
    - disk_Format: {{ }}
    {% if salt['network']['connect'](host='{{ address }}', port="9292")['result'] == True %}
    {% endif %}
    - onlyif:
      - fun: network.connect
        host: {{ address }}
        port: 9292

{% endfor %}
{% endfor %}
