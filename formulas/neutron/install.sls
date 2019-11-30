include:
  - formulas/openstack/common/repo

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
      - python2-networking-ovn

  {% endif %}

{% elif grains['os_family'] == 'RedHat' %}

  {% if pillar['neutron']['backend'] == "linuxbridge" %}
neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron-ml2
      - openstack-neutron
      - python2-openstackclient

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron
      - openstack-neutron-ml2
      - python2-openstackclient
      - python2-networking-ovn

  {% endif %}
{% endif %}
