include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/openstack/common/repo

rabbitmq_packages:
  pkg.installed:
    - pkgs:
      - rabbitmq-server
