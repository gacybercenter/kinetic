include:
  - formulas/controller/install
  - formulas/common/base
  - formulas/common/networking

{% if 'raid' in pillar['hosts']['controller']['kvm_disk_config']['type'] %}
{% set raid_level = pillar['hosts']['controller']['kvm_disk_config']['type'].split('raid') %}

kvm_array:
  raid.present:
    - name: /dev/md/kvm_array
    - level: {{ raid_level[1] }}
    - devices:
    {% for device in pillar['hosts']['controller']['kvm_disk_config']['members'] %}
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

{% elif 'standard' in pillar['hosts']['controller']['kvm_disk_config']['type'] %}
{% set target_device = pillar['hosts']['controller']['kvm_disk_config']['members'][0] %}
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

{% for os, args in pillar.get('images', {}).items() %}
/kvm/images/{{ args['local_name'] }}:
  file.managed:
    - source:
{% if args['local_url'] == "pull_from_mine" %}
{% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
{% for host in cache_addresses_dict %}
      - http://{{ cache_addresses_dict[host][0] }}/images/{{ args['local_name'] }}
{% endfor %}
{% else %}
      - {{ args['local_url'] }}
{% endif %}

{% if args['local_hash'] == "pull_from_mine" %}
{% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
{% for host in cache_addresses_dict %}
    - source_hash: http://{{ cache_addresses_dict[host][0] }}/images/checksums
{% endfor %}
{% else %}
    - source_hash: {{ args['local_hash'] }}
{% endif %}
    - source_hash_name: {{ args['local_source_hash_name'] }}
    - require:
      - /kvm/images

/kvm/images/{{ os }}-latest:
  file.symlink:
    - target: /kvm/images/{{ args['local_name'] }}
    - force: True
    - require:
      - /kvm/images/{{ args['local_name'] }}
{% endfor %}
