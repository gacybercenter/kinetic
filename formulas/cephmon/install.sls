include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/ceph/common/repo

install_ceph:
  pkg.installed:
    - name: ceph
    - require:
      - sls: /formulas/ceph/common/repo
