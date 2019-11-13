include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

erlang-base-hipe:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

erlang-hipe:
  pkg.installed

{% endif %}

rabbitmq-server:
  pkg.installed
