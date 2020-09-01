highstate_rabbitmq:
  local.state.highstate:
    - tgt_type: compound
    - tgt: 'E@(rabbitmq*) and G@production:True'
