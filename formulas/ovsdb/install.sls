include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

ovsdb_packages:
  pkg.installed:
    - pkgs:
      - ovn-central
      - openvswitch-switch

{% elif grains['os_family'] == 'RedHat' %}

ovsdb_packages:
  pkg.installed:
    - pkgs:
      - ovn-central
      - libibverbs
      - rdma-core
{% endif %}
