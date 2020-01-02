create_cinder_pool:
  local.cmd.run:
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph osd pool create volumes {{ data ['data']['pgs'] }}
