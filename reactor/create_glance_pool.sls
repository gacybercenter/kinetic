create_glance_pool:
  local.cmd.run:
    - tgt: 'spawning:0 and type:cephmon'
    - tgt_type: compound
    - arg:
      - touch /root/yayitworks
