uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - train
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu bionic-updates/train main
    - file: /etc/apt/sources.list.d/cloudarchive-train.list
    - keyid: ECD76E3E
    - keyserver: keyserver.ubuntu.com

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
    - dist_upgrade: True

designate_packages:
  pkg.installed:
    - pkgs:
      - designate
      - bind9
      - bind9utils
      - bind9-doc
      - designate-worker
      - designate-producer
      - designate-mdns
      - python3-memcache
      - python3-designateclient
      - python3-openstackclient
