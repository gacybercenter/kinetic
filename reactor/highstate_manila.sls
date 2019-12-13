highstate_manila:
  local.state.highstate:
    - tgt_type: compound
    - tgt: 'E@(manila*) and G@production:True'
