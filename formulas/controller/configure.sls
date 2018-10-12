include:
  - formulas/controller/install

{% if 'raid' in pillar['hosts']['cache']['controller']['kvm_disk_config']['type'] %}

foo:
  test.nop

{% endif %}

