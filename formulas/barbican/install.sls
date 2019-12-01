include:
  - formulas/openstack/common/repo

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
      - openstack-barbican-api
      - python2-openstackclient
      - httpd

{% endif %}
