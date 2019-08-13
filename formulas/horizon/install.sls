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

horizon_packages:
  pkg.installed:
    - pkgs:
      - python-openstackclient
      - python-heat-dashboard
      - python-pip
      - python-setuptools
      - python-designate-dashboard
      - openstack-dashboard

#python /usr/share/openstack-dashboard/manage.py compress:
#  cmd.run:
#    - onchanges:
#      - pkg: horizon_packages
