{% macro spawnzero_complete() %}
spawnzero_complete:
  grains.present:
    - value: True
  module.run:
    - name: mine.send
    - m_name: spawnzero_complete
    - kwargs:
        mine_function: grains.item
    - args:
      - spawnzero_complete
    - onchanges:
      - grains: spawnzero_complete
{% endmacro %}

{% macro check_spawnzero_status(type) %}
check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ type }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure
{% endmacro %}
