include:
  - formulas/openstack/common/repo

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
      - python-memcached
      - python-rbd
      - python-rados
      - python2-openstackclient

{% endif %}
