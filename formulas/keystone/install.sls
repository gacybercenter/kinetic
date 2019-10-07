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

keystone_packages:
  pkg.installed:
    - pkgs:
      - keystone
      - python3-pyldap
      - python3-ldappool
      - python3-openstackclient
      - ldap-utils
      - apache2
      - libapache2-mod-wsgi
