include:
  - formulas/openstack/common/repo



{% if grains['os_family'] == 'Debian' %}

python3-memcache:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

python-memcached:
  pkg.installed

{% endif %}

memcached:
  pkg.installed
