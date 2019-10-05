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

neutron_packages:
  pkg.installed:
    - pkgs:
      - neutron-server
      - neutron-plugin-ml2
      - neutron-linuxbridge-agent
      - neutron-l3-agent
      - neutron-dhcp-agent
      - neutron-metadata-agent
      - python3-openstackclient
      - python3-tornado
