include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

placement_packages:
  pkg.installed:
    - pkgs:
      - python3-openstackclient
      - placement-api
      - python3-pymysql

{% elif grains['os_family'] == 'RedHat' %}

placement_packages:
  pkg.installed:
    - pkgs:
      - python3-openstackclient
      - openstack-placement-api
      - python3-PyMySQL

{% endif %}
