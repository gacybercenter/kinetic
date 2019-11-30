include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

network_packages:
  pkg.installed:
    - pkgs:
      - neutron-plugin-ml2
      - neutron-linuxbridge-agent
      - neutron-l3-agent
      - neutron-dhcp-agent
      - neutron-metadata-agent
      - python3-openstackclient
      - python3-tornado

{% elif grains['os_family'] == 'RedHat' %}

network_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron-ml2
      - openstack-neutron-linuxbridge
      - ebtables
      - python2-openstackclient

{% endif %}
