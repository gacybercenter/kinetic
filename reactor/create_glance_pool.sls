create_glance_pool:
  local.cmd.run:
    - tgt: 'type:cephmon'
    - tgt_type: grain
    - arg:
      - touch /root/yayitworks
