{% set sleep = range(1, 10) | random %}
{% set type = pillar['type'] %}

test_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - echo {{ pillar['type'] }}
