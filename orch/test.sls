{% set sleep = range(1, 10) | random %}
{% set type = pillar['type'] %}

sleep_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep {{ sleep }}

test_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - echo {{ pillar['type'] }}
