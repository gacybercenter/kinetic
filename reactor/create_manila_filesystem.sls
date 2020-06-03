create_manila_filesystem:
  local.cmd.run:
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph osd pool create fileshare_data && ceph osd pool create fileshare_metadata && ceph fs new manila fileshare_metadata fileshare_data
