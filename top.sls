{% set type = opts.id.split('-')[0] %}
{% set role = salt['pillar.get']('hosts:'+type+':role', type) %}

base:
  '*':
    - /formulas/common/base
  {{ type }}*:
    - /formulas/{{ role }}/configure
