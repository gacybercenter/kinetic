include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

designate_packages:
  pkg.installed:
    - pkgs:
      - bind9utils
      - designate
      - designate-worker
      - designate-producer
      - designate-mdns
      - python3-memcache
      - python3-designateclient
      - python3-openstackclient
      - python3-pip

pymemcache:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true
    - require:
      - pkg: designate_packages

{% elif grains['os_family'] == 'RedHat' %}

designate_packages:
  pkg.installed:
    - pkgs:
      - bind
      - openstack-designate-api
      - openstack-designate-mdns
      - openstack-designate-producer
      - openstack-designate-worker
      - openstack-designate-central
      - python-memcached
      - python2-designateclient
      - python2-openstackclient
      - python2-pip
    - reload_modules: True

pymemcache:
  pip.installed:
    - bin_env: '/usr/bin/pip'    
    - require:
      - pkg: designate_packages

{% endif %}
