include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/ceph/repo

install_ceph:
  pkg.installed:
    - name: ceph
    - require:
      - sls: /formulas/common/ceph/repo
