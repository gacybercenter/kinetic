testing reactor:
  local.cmd.run:
    - tgt: 'salt'
    - arg:
      - echo {{ data['data']['raw'] }} > /root/foo
