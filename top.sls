base:
  '*':
    - formulas/common/base
{% if grains['type'] %}
  {{ grains['type'] }}*:
    - formulas/{{ grains['type'] }}/configure
{% endif %}
