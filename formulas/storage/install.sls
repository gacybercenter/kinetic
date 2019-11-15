include:
  - formulas/ceph/common/repo

install_ceph:
  pkg.installed:
    - name: ceph
    - require:
      - pkgrepo: ceph_repo
