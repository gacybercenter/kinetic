include:
  - formulas/openstack/common/repo

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
      - python2-openstackclient
      - uwsgi-plugin-python2-tornado
      - python2-designateclient
      - python2-pip
    - reload_modules: true

zunclient_install:
  pip.installed:
    - name: python-zunclient

{% endif %}
