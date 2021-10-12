set_vms_pool_pgs:
  local.cmd.run:
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph osd pool set vms pg_num {{ data['data']['pgs'] }}