highstate_manila:
  local.state.highstate:
    - tgt_type: compound
    - tgt: 'E@(manila*|share*) and G@production:True'
