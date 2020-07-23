include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

mariadb_packages:
  pkg.installed:
    - pkgs:
      - mariadb-server
      - python3-pymysql
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

mariadb_packages:
  pkg.installed:
    - pkgs:
      - mariadb-server-galera
      - mariadb
      - python3-PyMySQL
    - reload_modules: True

{% endif %}
