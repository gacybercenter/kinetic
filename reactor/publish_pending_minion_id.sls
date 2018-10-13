{% set type = data['raw'].split('-') %}

testing reactor:
  local.cmd.run:
    - tgt: 'salt'
    - arg:
      - touch /root/{{ type[0] }}/{{ data['raw'] }}
