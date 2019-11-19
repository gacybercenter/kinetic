include:
  - formulas/openstack/common/repo
  - formulas/ceph/common/repo

{% if grains['os_family'] == 'Debian' %}

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


{% elif grains['os_family'] == 'RedHat' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-compute
      - openstack-neutron-linuxbridge
      - python-tornado
      - ceph-common
      - spice-html5
      - python-rbd
      - python-rados

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-compute
      - ovn-host
      - python2-networking-ovn-metadata-agent
      - python-tornado
      - ceph-common
      - spice-html5
      - python-rbd
      - python-rados

  {% endif %}

{% endif %}
