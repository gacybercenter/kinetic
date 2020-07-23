include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

python3-memcache:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

python3-memcached:
  pkg.installed

{% endif %}

memcached:
  pkg.installed
