{% set type = data['raw'].split('-') %}

testing reactor:
  local.cmd.run:
    - tgt: 'salt'
    - arg:
      - mkdir -p /tmp/{{ type[0] }} && touch /tmp/{{ type[0] }}/{{ data['raw'] }}
