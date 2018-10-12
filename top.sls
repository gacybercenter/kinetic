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
