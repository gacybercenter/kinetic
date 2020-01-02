highstate_mysql:
  local.state.highstate:
    - tgt_type: compound
    - tgt: 'E@(mysql*) and G@production:True'
