include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

heat_packages:
  pkg.installed:
    - pkgs:
      - heat-api
      - heat-api-cfn
      - heat-engine
      - python3-openstackclient
      - python3-tornado
      - python3-zunclient
      - python3-designateclient

{% elif grains['os_family'] == 'RedHat' %}

heat_packages:
  pkg.installed:
    - pkgs:
      - openstack-heat-api
      - openstack-heat-api-cfn
      - openstack-heat-engine
      - python3-openstackclient
      - uwsgi-plugin-python3-tornado
      - python3-designateclient
      - python3-pip
    - reload_modules: true

zunclient_install:
  pip.installed:
    - name: python-zunclient
    - bin_env: '/usr/bin/pip3'
    - require:
      - pkg: heat_packages
    - reload_modules: True

{% endif %}
