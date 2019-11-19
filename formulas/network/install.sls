include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

neutron_packages:
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
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron-ml2
      - openstack-neutron-linuxbridge
      - ebtables
      - python2-openstackclient

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron-ml2
      - python2-networking-ovn
      - ovn-central
      - ovn
      - ebtables
      - python2-openstackclient

  {% endif %}
{% endif %}
