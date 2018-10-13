testing reactor:
  local.cmd.run:
    - tgt: 'salt'
    - arg:
      - echo {{ data['raw'] }} > /root/foo
