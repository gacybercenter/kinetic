include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

manila_packages:
  pkg.installed:
    - pkgs:
      - manila-api
      - manila-scheduler
      - python3-openstackclient
      - python3-manilaclient
      - python3-memcache

{% elif grains['os_family'] == 'RedHat' %}

manila_packages:
  pkg.installed:
    - pkgs:
      - openstack-manila
      - python2-openstackclient
      - python2-manilaclient
      - python-memcached

{% endif %}
