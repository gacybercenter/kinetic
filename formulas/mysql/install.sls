include:
  - formulas/openstack/common/repo

{% if grains['os_family'] == 'Debian' %}

mariadb_repo:
  pkgrepo.managed:
    - humanname: MariaDB 10.3
    - name: deb http://ftp.osuosl.org/pub/mariadb/repo/10.3/ubuntu bionic main
    - file: /etc/apt/sources.list.d/mariadb-10.3.list
    - keyid: C74CD1D8
    - keyserver: keyserver.ubuntu.com

update_packages_mariadb:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: mariadb_repo
    - dist_upgrade: True

mariadb-server:
  pkg.installed:
    - require:
      - pkgrepo: mariadb_repo

galera:
  pkg.installed:
    - require:
      - pkgrepo: mariadb_repo

python3-pymysql:
  pkg.installed:
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

mariadb-server-galera:
  pkg.installed

mariadb:
  pkg.installed

patch:
  pkg.installed:
    - reload_modules: True

python36-PyMySQL:
  pkg.installed:
    - reload_modules: True

python36-mysql:
  pkg.installed:
    - reload_module: True

/usr/lib/python3.6/site-packages:
  file.patch:
    - source: https://patch-diff.githubusercontent.com/raw/saltstack/salt/pull/56174.patch
    - skip_verify: True
    - require:
      - pkg: patch

{% endif %}
