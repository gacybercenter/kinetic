{% if grains['os_family'] == 'Debian' %}

mariadb_repo:
  pkgrepo.managed:
    - humanname: mariadb10.5
    - name: deb http://downloads.mariadb.com/MariaDB/mariadb-10.5/repo/ubuntu focal main
    - file: /etc/apt/sources.list.d/mariadb.list
    - keyid: F1656F24C74CD1D8
    - keyserver: keyserver.ubuntu.com

mariadb_maxscale_repo:
  pkgrepo.managed:
    - humanname: mariadb_maxscale
    - name: deb http://downloads.mariadb.com/MaxScale/2.4/ubuntu focal main
    - file: /etc/apt/sources.list.d/mariadb_maxscale.list
    - keyid: 135659E928C12247
    - keyserver: keyserver.ubuntu.com

mariadb_tools_repo:
  pkgrepo.managed:
    - humanname: mariadb_tools
    - name: deb http://downloads.mariadb.com/Tools/ubuntu focal main
    - file: /etc/apt/sources.list.d/mariadb_tools.list
    - keyid: CE1A3DD5E3C94F49
    - keyserver: keyserver.ubuntu.com

update_packages_mariadb:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - mariadb_tools_repo
      - mariadb_maxscale_repo
      - mariadb_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

mariadb_repo:
  pkgrepo.managed:
    - name: mariadb
    - file: /etc/yum.repos.d/mariadb.repo
    - baseurl: https://downloads.mariadb.com/MariaDB/mariadb-10.5/yum/centos/$releasever/$basearch
    - gpgkey: https://downloads.mariadb.com/MariaDB/MariaDB-Server-GPG-KEY
    - module_hotfixes: 1

mariadb_maxscale_repo:
  pkgrepo.managed:
    - name: mariadb_maxscale
    - file: /etc/yum.repos.d/mariadb_maxscale.repo
    - baseurl: https://downloads.mariadb.com/MaxScale/2.4/centos/$releasever/$basearch
    - gpgkey: https://downloads.mariadb.com/MaxScale/MariaDB-MaxScale-GPG-KEY

mariadb_tools_repo:
  pkgrepo.managed:
    - name: mariadb_tools
    - file: /etc/yum.repos.d/mariadb_tools.repo
    - baseurl: https://downloads.mariadb.com/Tools/centos/$releasever/$basearch
    - gpgkey: https://downloads.mariadb.com/Tools/MariaDB-Enterprise-GPG-KEY

update_packages_mariadb:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - mariadb_tools_repo
      - mariadb_maxscale_repo
      - mariadb_repo

{% endif %}
