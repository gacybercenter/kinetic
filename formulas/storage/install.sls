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

## This is for the current method of dealing with dynamic journal Creation
## this should eventually be dropped and the current __slot__ mechanism
## be turned into a custom module, or do a PR against the current
## ceph modules to bring them up to date
install_jq:
  pkg.installed:
    - name: jq
