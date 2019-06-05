base:
  '*':
    - formulas/common/base
  {{ opts.id.split('-') }}*:
    - formulas/grains['type']/configure
