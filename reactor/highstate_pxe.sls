highstate_pxe:
  local.state.apply:
    - tgt: 'pxe'
