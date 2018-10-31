{% set type = pillar['type'] %}

test_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - echo {{ type }}
