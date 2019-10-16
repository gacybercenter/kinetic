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

heat_packages:
  pkg.installed:
    - pkgs:
      - heat-api
      - heat-api-cfn
      - heat-engine
      - python3-openstackclient
      - python3-tornado
      - python3-zunclient
      - python3-designateclient
