include:
  - /formulas/openstack/common/repo
  - /formulas/common/base
  - /formulas/common/networking
  
rabbitmq_packages:
  pkg.installed:
    - pkgs:
      - rabbitmq-server
