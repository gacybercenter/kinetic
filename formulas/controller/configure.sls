include:
  - formulas/controller/install

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
  blockdev.formatted:
    - name: /dev/mapper/kvm_vg-kvm_lv
    - fs_type: xfs
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

/kvm/images:
  file.directory:
    - makedirs: True
    - require:
      - /kvm

{% for os, args in pillar.get('images', {}).items() %}
/kvm/images/{{ args['local_name'] }}:
  file.managed:
    - source:
      - {{ args['local_url'] }}
    - source_hash: {{ args['local_hash'] }}
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

{% for network, interface in pillar['hosts']['controller']['networks'] %}
echo {{ network }} {{ interface }}:
  cmd.run
{% endfor %}

