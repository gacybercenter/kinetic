include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

sahara_packages:
  pkg.installed:
    - pkgs:
      - apache2
      - sahara
      - sahara-api
      - sahara-engine
      - python3-saharaclient
      - python3-openstackclient

{% elif grains['os_family'] == 'RedHat' %}

sahara_packages:
  pkg.installed:
    - pkgs:
      - openstack-sahara-api
      - openstack-sahara-engine
      - openstack-sahara
      - python2-saharaclient
      - python2-openstackclient

{% endif %}
