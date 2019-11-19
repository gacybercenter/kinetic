include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - neutron-server
      - neutron-plugin-ml2
      - python3-openstackclient
      - python3-tornado

{% elif grains['os_family'] == 'RedHat' %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron
      - openstack-neutron-ml2
      - python2-openstackclient

{% endif %}
