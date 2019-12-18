include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

designate_packages:
  pkg.installed:
    - pkgs:
      - designate
      - designate-worker
      - designate-producer
      - designate-mdns
      - python3-memcache
      - python3-designateclient
      - python3-openstackclient

{% elif grains['os_family'] == 'RedHat' %}

designate_packages:
  pkg.installed:
    - pkgs:
      - openstack-designate-api
      - openstack-designate-mdns
      - openstack-designate-producer
      - openstack-designate-worker
      - openstack-designate-central
      - python-memcached
      - python2-designateclient
      - python2-openstackclient

{% endif %}
