{% if grains['os_family'] == 'Debian' %}

uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - Train
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

{% elif grains['os_family'] == 'RedHat' %}

rdo:
  pkg.installed:
    - name: centos-release-openstack-train

update_packages_rdo:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkg: rdo

openstack-selinux:
  pkg.installed:
    - require:
      - pkg: rdo
      - pkg: update_packages_rdo

{% endif %}
