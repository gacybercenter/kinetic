highstate_haproxy:
  local.state.highstate:
    - tgt_type: compound
    - tgt: 'E@(haproxy*) and G@production:True'
