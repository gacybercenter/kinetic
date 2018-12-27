include:
  - formulas/cephmon/install
  - formulas/common/base
  - formulas/common/networking

mine.update:
  module.run:
    - network.ip_addrs: [ens3]
    - grains.get: id

foo:
  test.nop
