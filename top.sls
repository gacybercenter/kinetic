{% set type = opts.id.split('-')[0] %}

base:
  '*':
    - formulas/common/base
  {{ type }}*:
    - formulas/{{ type }}/configure
