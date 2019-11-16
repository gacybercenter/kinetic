include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

designate_packages:
  pkg.installed:
    - pkgs:
      - designate
      - bind9
      - bind9utils
      - bind9-doc
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
      - bind
      - bind-utils
      - python-memcached
      - python2-designateclient
      - python2-openstackclient

{% endif %}
