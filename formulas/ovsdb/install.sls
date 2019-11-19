include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

ovsdb_packages:
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

ovsdb_packages:
  pkg.installed:
    - pkgs:
      - python2-networking-ovn
      - ovn-central
      - ovn
      - ebtables

  {% endif %}
{% endif %}
