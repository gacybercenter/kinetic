{% set sleep = range(1, 10) | random %}
{% set type = pillar['type'] %}

sleep5_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 5
  

test_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - echo {{ pillar['type'] }}
