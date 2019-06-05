base:
  '*':
    - formulas/common/base
{% if grains['type'] == opts.id.split('-') %}
  grains['type']*:
    - formulas/grains['type']/configure
{% endif %}
