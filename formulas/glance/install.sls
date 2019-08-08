ceph_repo:
  pkgrepo.managed:
    - humanname: Ceph Nautilus
    - name: deb https://download.ceph.com/debian-nautilus/ bionic main
    - file: /etc/apt/sources.list.d/ceph.list
    - key_url: https://download.ceph.com/keys/release.asc

uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - Rocky
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu bionic-updates/rocky main
    - file: /etc/apt/sources.list.d/cloudarchive-rocky.list
    - keyid: ECD76E3E
    - keyserver: keyserver.ubuntu.com

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
      - pkgrepo: ceph_repo
    - dist_upgrade: True

glance_packages:
  pkg.installed:
    - pkgs:
      - glance
      - python-memcache
      - python-rbd
      - python-rados
      - python-openstackclient
      - ceph-common
