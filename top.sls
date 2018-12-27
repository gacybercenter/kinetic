base:
  '*':
    - formulas/common/base
  salt:
    - formulas/salt/configure
  pxe:
    - formulas/pxe/configure
  cache*:
    - formulas/cache/configure
  controller*:
    - formulas/controller/configure
  storage*:
    - formulas/storage/configure
  compute*:
    - formulas/compute/configure
  cephmon*:
    - formulas/cephmon/configure
