include:
  - /formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

nova_packages:
  pkg.installed:
    - pkgs:
      - nova-api
      - nova-conductor
      - nova-spiceproxy
      - nova-scheduler
      - python3-openstackclient
      - git

{% elif grains['os_family'] == 'RedHat' %}

nova_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-api
      - openstack-nova-conductor
      - openstack-nova-spicehtml5proxy
      - openstack-nova-scheduler
      - python3-openstackclient
      - git

{% endif %}
