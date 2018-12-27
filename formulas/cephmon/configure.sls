include:
  - formulas/cephmon/install
  - formulas/common/base
  - formulas/common/networking

mine.update:
  module.run:
    - network.interfaces: []

foo:
  test.nop
