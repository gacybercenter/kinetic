{% set type = {{ data['raw'] }}.split('-') %}

testing reactor:
  local.cmd.run:
    - tgt: 'salt'
    - arg:
      - echo {{ data['raw'] }} > /root/{{ type[0] }}
