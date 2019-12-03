create_manila_data_pool:
  local.cmd.run:
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph osd pool create fileshare_data {{ data ['data']['data_pgs'] }}

create_manila_metadata_pool:
  local.cmd.run:
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph osd pool create fileshare_metadata {{ data ['data']['metadata_pgs'] }}

create_manila_filesystem:
  local.cmd.run:
    - tgt: 'G@spawning:0 and G@type:cephmon'
    - tgt_type: compound
    - arg:
      - ceph fs new manila fileshare_metadata fileshare_data
    - require:
      - cmd: create_manila_data_pool
      - cmd: create_manila_metadata_pool
