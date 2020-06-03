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

PowerTools:
  pkgrepo.managed:
    - humanname: CentOS PowerTools
    - name: PowerTools
    - mirrorlist: http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=PowerTools&infra=$infra
    - file: /etc/yum.repos.d/PowerTools.repo
    - gpgkey: file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

rdo:
  pkg.installed:
    - name: centos-release-openstack-ussuri

update_packages_rdo:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkg: rdo
      - pkg: PowerTools

openstack-selinux:
  pkg.installed:
    - require:
      - pkg: rdo
      - pkg: update_packages_rdo

{% endif %}
