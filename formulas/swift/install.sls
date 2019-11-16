include:
  - formulas/openstack/common/repo
  - formulas/ceph/common/repo

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
      - python2-openstackclient

{% endif %}
