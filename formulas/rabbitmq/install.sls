include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

rabbitmq_packages:
  pkg.installed:
    - pkgs:
      - rabbitmq-server
