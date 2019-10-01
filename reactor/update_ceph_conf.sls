update_ceph_conf_{{ data }}:
  local.state.apply:
    - tgt_type: pcre
    - tgt: '(cephmon*|cinder*|compute*|glance*|storage*|swift*)'
    - name: state.apply
    - args:
      - mods: formulas/ceph/common/configure
