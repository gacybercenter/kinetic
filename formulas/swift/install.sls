include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo
  - /formulas/common/ceph/repo

{% if grains['os_family'] == 'Debian' %}

swift_packages:
  pkg.installed:
    - pkgs:
      - radosgw
      - python3-openstackclient

{% elif grains['os_family'] == 'RedHat' %}

swift_packages:
  pkg.installed:
    - pkgs:
      - ceph-radosgw
      - python3-openstackclient

{% endif %}
