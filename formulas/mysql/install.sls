include:
  - formulas/openstack/common/repo


## Patch that works around https://github.com/GeorgiaCyber/kinetic/issues/51
## Remove this when its officially merged

{% if grains['saltversion'] == '3000' %}
{% for patch in ["modules/mysql.py", "states/mysql_user.py"] %}
{{ grains['saltpath'] }}/{{ patch }}:
  file.managed:
    - source: https://raw.githubusercontent.com/saltstack/salt/5bfd67c13ec75f912f3b57ac33bf42d38b6dc47d/salt/{{ patch }}
    - skip_verify: True
{% endfor %}
{% endif %}

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

python3-PyMySQL:
  pkg.installed:
    - reload_modules: True

{% endif %}
