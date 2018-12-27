include:
  - formulas/cephmon/install
  - formulas/common/base
  - formulas/common/networking

mine.send:
  module.run:
    - network.ip_addrs: [ens3]

foo:
  test.nop
