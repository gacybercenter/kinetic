include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

glance_packages:
  pkg.installed:
    - pkgs:
      - glance
      - python3-memcache
      - python3-rbd
      - python3-rados
      - python3-openstackclient

{% elif grains['os_family'] == 'RedHat' %}

glance_packages:
  pkg.installed:
    - pkgs:
      - openstack-glance
      - python3-memcached
      - python3-rbd
      - python3-rados
      - python3-openstackclient

{% endif %}
