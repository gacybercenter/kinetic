{% set type = opts.id.split('-')[0] %}

base:
  '*':
    - formulas/common/base
  {{ opts.id.split('-')[0] }}*:
    - formulas/grains['type']/configure
