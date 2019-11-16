include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

horizon_packages:
  pkg.installed:
    - pkgs:
      - python3-openstackclient
      - python3-heat-dashboard
      - python3-pip
      - python3-setuptools
      - python3-designate-dashboard
      - openstack-dashboard
      - git

{% elif grains['os_family'] == 'RedHat' %}

horizon_packages:
  pkg.installed:
    - pkgs:
      - python2-openstackclient
      - openstack-heat-ui
      - python2-pip
      - python2-setuptools
      - openstack-designate-ui
      - openstack-dashboard
      - git

{% endif %}
