{% if opts.id not in ['salt', 'pxe'] %}
  {% set type = opts.id.split('-')[0] %}
  {% if pillar['hosts'][type]['style'] == 'physical' %}
    {% set role = pillar['hosts'][type]['role'] %}
  {% else %}
    {% set role = type %}
  {% endif %}
{% else %}
  {% set type = opts.id %}
  {% set role = type %}
{% endif %}

base:
  '*':
    - /formulas/common/base
  {{ type }}*:
    - /formulas/{{ role }}/configure
