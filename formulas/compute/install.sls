include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo
  - /formulas/common/ceph/repo
  - /formulas/common/frr/repo

{% if grains['os_family'] == 'Debian' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - nova-compute
      - neutron-linuxbridge-agent
      - python3-tornado
      - ceph-common
      - spice-html5
      - python3-rbd
      - python3-rados
      - frr
      - frr-pythontools

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

compute_packages:
  pkg.installed:
    - pkgs:
      - nova-compute
      - python3-tornado
      - ceph-common
      - spice-html5
      - python3-rbd
      - python3-rados
      - ovn-host
      - neutron-ovn-metadata-agent
      - haproxy
      - frr
      - frr-pythontools

  {% endif %}

{% elif grains['os_family'] == 'RedHat' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-compute
      - openstack-neutron-linuxbridge
      - python3-tornado
      - ceph-common
      - python3-rbd
      - python3-rados
      - conntrack-tools
      - frr
      - frr-pythontools

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-compute
      - ovn-host
      - openstack-neutron-ovn-metadata-agent
      - python3-tornado
      - ceph-common
      - python3-rbd
      - python3-rados
      - openstack-neutron-common
      - haproxy
      - frr
      - frr-pythontools

  {% endif %}

{% endif %}
