include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

mariadb-server:
  pkg.installed

python3-pymysql:
  pkg.installed:
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

mariadb-server:
  pkg.installed

mariadb:
  pkg.installed

python36-PyMySQL:
  pkg.installed:
    - reload_modules: True

python36-mysql:
  pkg.installed:
    - reload_module: True

{% endif %}
