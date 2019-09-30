{% set type = opts.id.split('-')[0] %}

dev:
  '*':
    - formulas/common/base
  {{ type }}*:
    - formulas/{{ type }}/configure
