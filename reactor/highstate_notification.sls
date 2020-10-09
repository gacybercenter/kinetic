highstate_{{ data['id'] }}:
  local.state.highstate:
    - tgt_type: compound
    - tgt: 'E@(designate*|bind*|haproxy*|manila*|share*|mysql*|pxe) and G@build_phase:configure'
