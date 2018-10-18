{% set host = pillar['host'] %}

highstate_{{ host }}:
  salt.state:
    - tgt: '{{ host }}'
    - highstate: True
