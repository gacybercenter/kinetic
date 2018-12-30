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

keystone_packages:
  pkg.installed:
    - pkgs:
      - keystone
      - python-pyldap
      - python-ldappool
      - python-openstackclient
      - ldap-utils
      - apache2
      - libapache2-mod-wsgi
