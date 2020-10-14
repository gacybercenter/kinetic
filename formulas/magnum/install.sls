include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

magnum_packages:
  pkg.installed:
    - pkgs:
      - magnum-api
      - magnum-conductor
      - python3-magnumclient
      - python3-openstackclient

{% elif grains['os_family'] == 'RedHat' %}

magnum_packages:
  pkg.installed:
    - pkgs:
      - openstack-magnum-api
      - openstack-magnum-conductor
      - python3-magnumclient
      - python3-openstackclient

{% endif %}
