create_glance_pool:
  local.salt.function:
    - name: cmd.run
    - tgt: 'type:cephmon'
    - tgt_type: grain
    - arg:
      - touch /root/yayitworks
