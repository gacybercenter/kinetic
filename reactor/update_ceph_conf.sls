update_ceph_conf_{{ data['id'] }}:
  local.state.apply:
    - tgt_type: compound
    - tgt: 'E@(cephmon*|cinder*|compute*|glance*|storage*|swift*|mds*|manila*|share*) and G@production:True'
    - args:
      - mods: formulas/ceph/common/configure
