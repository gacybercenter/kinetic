include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

bind_packages:
  pkg.installed:
    - pkgs:
      - bind9
      - bind9utils
      - bind9-doc

{% elif grains['os_family'] == 'RedHat' %}

bind_packages:
  pkg.installed:
    - pkgs:
      - bind
      - bind-utils

{% endif %}
