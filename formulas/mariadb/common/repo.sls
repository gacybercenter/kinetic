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

ceph_repo:
  pkgrepo.managed:
    - name: ceph
    - baseurl: https://download.ceph.com/rpm-octopus/el8/$basearch
    - file: /etc/yum.repos.d/ceph.repo
    - gpgkey: https://download.ceph.com/keys/release.asc

## new requirement with octopus+el8
ceph_repo_noarch:
  pkgrepo.managed:
    - name: ceph_noarch
    - baseurl: https://download.ceph.com/rpm-octopus/el8/noarch
    - file: /etc/yum.repos.d/ceph_noarch.repo
    - gpgkey: https://download.ceph.com/keys/release.asc

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: ceph_repo
      - pkgrepo: ceph_repo_noarch

{% endif %}
