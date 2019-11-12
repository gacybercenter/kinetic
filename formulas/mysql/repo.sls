include:
  - formulas/openstack/common/repo

mariadb-server:
  pkg.installed

python3-pymysql:
  pkg.installed:
    - reload_modules: True
