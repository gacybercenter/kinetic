include:
  - formulas/openstack/common/repo
  - formulas/ceph/common/repo

{% if grains['os_family'] == 'Debian' %}

cinder_packages:
  pkg.installed:
    - pkgs:
      - cinder-api
      - cinder-scheduler
      - python3-openstackclient
      - python3-memcache

{% elif grains['os_family'] == 'RedHat' %}

cinder_packages:
  pkg.installed:
    - pkgs:
      - openstack-cinder
      - python2-openstackclient
      - python-memcached

{% endif %}
