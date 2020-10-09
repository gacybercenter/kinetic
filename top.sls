{% if opts.id not in ['salt', 'pxe'] %}
  {% set type = opts.id.split('-')[0] %}
    {% set role = salt['pillar.get']('hosts:'+type+':role', type) %}
{% else %}
  {% set type = opts.id %}
  {% set role = type %}
{% endif %}

base:
  '*':
    - /formulas/common/base
  {{ type }}*:
    - /formulas/{{ role }}/configure
