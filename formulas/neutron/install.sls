include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}
    {% if pillar['neutron']['backend'] == "linuxbridge" %}
neutron_packages:
  pkg.installed:
    - pkgs:
      - neutron-server
      - neutron-plugin-ml2
      - python3-openstackclient
      - python3-tornado

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - neutron-server
      - neutron-plugin-ml2
      - python3-openstackclient
      - python3-tornado

  {% endif %}

{% elif grains['os_family'] == 'RedHat' %}

  {% if pillar['neutron']['backend'] == "linuxbridge" %}
neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron-ml2
      - openstack-neutron
      - python3-openstackclient

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron
      - openstack-neutron-ml2
      - python3-openstackclient
      - libibverbs
      - rdma-core

  {% endif %}
{% endif %}
