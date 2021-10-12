set_images_pool_pgs:
  salt.function:
    - name: cmd.run
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph osd pool set images pg_num {{ data['data']['pgs'] }}