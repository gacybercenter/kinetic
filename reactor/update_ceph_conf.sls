update_ceph_conf_{{ data['id'] }}:
  local.state.apply:
    - tgt_type: pcre
    - tgt: '(cephmon*|cinder*|compute*|glance*|storage*|swift*)'
    - args:
      - mods: formulas/ceph/common/configure
      - concurrent: true
