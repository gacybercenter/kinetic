include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/mariadb/repo

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
      - MariaDB-server
      - python3-PyMySQL
    - reload_modules: True

{% endif %}
