create_volumes_pool:
  salt.function:
    - name: cmd.run
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph osd pool set volumes pg_num {{ data ['data']['pgs'] }}