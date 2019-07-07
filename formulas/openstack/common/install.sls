uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - Stein
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu bionic-updates/stein main
    - file: /etc/apt/sources.list.d/cloudarchive-stein.list
    - keyid: ECD76E3E
    - keyserver: keyserver.ubuntu.com

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
    - dist_upgrade: True
