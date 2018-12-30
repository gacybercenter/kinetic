ceph_repo:
  pkgrepo.managed:
    - humanname: Ceph Mimic
    - name: deb https://download.ceph.com/debian-mimic/ bionic main
    - file: /etc/apt/sources.list.d/ceph.list
    - key_url: https://download.ceph.com/keys/release.asc

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - ceph_repo
    - dist_upgrade: True

install_ceph:
  pkg.installed:
    - name: ceph
    - require:
      - pkgrepo: ceph_repo

mdadm:
  pkg.installed
