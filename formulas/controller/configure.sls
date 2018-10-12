include:
  - formulas/controller/install

{% if 'raid' in pillar['hosts']['controller']['kvm_disk_config']['type'] %}

foo:
  test.nop

{% endif %}

