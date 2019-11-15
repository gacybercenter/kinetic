include:
  - formulas/openstack/common/repo

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
      - python2-openstackclient
      - openstack-placement-api
      - python36-PyMySQL

{% endif %}
