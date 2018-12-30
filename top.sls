base:
  '*':
    - formulas/common/base
  {{ grains['type'] }}*:
    - formulas/{{ grains['type'] }}/configure
