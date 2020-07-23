include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

barbican_packages:
  pkg.installed:
    - pkgs:
      - barbican-api
      - barbican-keystone-listener
      - barbican-worker
      - python3-openstackclient

{% elif grains['os_family'] == 'RedHat' %}

barbican_packages:
  pkg.installed:
    - pkgs:
      - openstack-barbican
      - openstack-barbican-api
      - openstack-barbican-keystone-listener
      - openstack-barbican-worker
      - python3-openstackclient
      - httpd
      - python3-mod_wsgi

{% endif %}
