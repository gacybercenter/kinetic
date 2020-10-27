include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

etcd_packages:
  pkg.installed:
    - pkgs:
      - etcd

{% elif grains['os_family'] == 'RedHat' %}

etcd_packages:
  pkg.installed:
    - pkgs:
      - etcd

{% endif %}
