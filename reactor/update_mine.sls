{% if opts.id not in ['salt', 'pxe'] %}
  {% set type = opts.id.split('-')[0] %}
{% else %}
  {% set type = opts.id %}
{% endif %}

update_mine:
  runner.mine.update:
    - args:
      - tgt: {{ type }}*
