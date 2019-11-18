include:
  - formulas/ceph/common/repo

install_ceph:
  pkg.installed:
    - name: ceph
    - require:
      - sls: formulas/ceph/common/repo

install_jq:
  pkg.installed:
    - name: jq
