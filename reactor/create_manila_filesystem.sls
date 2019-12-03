create_manila_filesystem:
  local.cmd.run:
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph osd pool create fileshare_data {{ data ['data']['data_pgs'] }} && ceph osd pool create fileshare_metadata {{ data ['data']['metadata_pgs'] }} && ceph fs new manila fileshare_metadata fileshare_data
