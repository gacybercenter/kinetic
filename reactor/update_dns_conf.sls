update_dns_conf:
  local.state.highstate:
    - tgt_type: compound
    - tgt: 'E@(designate*|bind*) and G@production:True'
