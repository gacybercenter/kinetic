uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - train
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu bionic-updates/train main
    - file: /etc/apt/sources.list.d/cloudarchive-train.list
    - keyid: ECD76E3E
    - keyserver: keyserver.ubuntu.com

ceph_repo:
  pkgrepo.managed:
    - humanname: Ceph Nautilus
    - name: deb https://download.ceph.com/debian-nautilus/ bionic main
    - file: /etc/apt/sources.list.d/ceph.list
    - key_url: https://download.ceph.com/keys/release.asc

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
    - dist_upgrade: True

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - ceph_repo
    - dist_upgrade: True

swift_packages:
  pkg.installed:
    - pkgs:
      - radosgw
      - python3-openstackclient
