include:
  - formulas/controller/install

{% if 'raid' in pillar['hosts']['controller']['kvm_disk_config']['type'] %}

{% set raid_level = pillar['hosts']['controller']['kvm_disk_config']['type'].split('raid') %}

kvm_array:
  raid.present:
    - name: /dev/kvm_array
    - level: {{ raid_level[1] }}
    - devices:
    {% for device in pillar['hosts']['controller']['kvm_disk_config']['members'] %}
      - {{ device }}
    {% endfor %}

{% endif %}

