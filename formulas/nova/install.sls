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
    - dist_upgrade: True

nova_packages:
  pkg.installed:
    - pkgs:
      - nova-api
      - nova-conductor
      - nova-consoleauth
      - nova-spiceproxy
      - nova-novncproxy
      - nova-scheduler
      - python-openstackclient
      - nova-placement-api
      - spice-html5
