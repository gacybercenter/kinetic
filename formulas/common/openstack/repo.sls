{% if grains['os_family'] == 'Debian' %}
  {% if grains['oscodename'] != 'focal' %}
uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - Ussuri
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu focal-updates/ussuri main
    - file: /etc/apt/sources.list.d/cloudarchive-ussuri.list
    - keyid: ECD76E3E
    - keyserver: keyserver.ubuntu.com

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
    - dist_upgrade: True
  {% endif %}

{% elif grains['os_family'] == 'RedHat' %}

## added per https://www.rdoproject.org/install/packstack/
## official upstream docs do not reflect this yet
CentOS-PowerTools:
  pkgrepo.managed:
    - humanname: CentOS-PowerTools
    - name: CentOS-PowerTools
    - mirrorlist: http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=PowerTools&infra=$infra
    - file: /etc/yum.repos.d/CentOS-PowerTools.repo
    - gpgkey: file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

rdo:
  pkg.installed:
    - name: centos-release-openstack-ussuri

update_packages_rdo:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkg: rdo
      - pkgrepo: CentOS-PowerTools

openstack-selinux:
  pkg.installed:
    - require:
      - pkg: rdo
      - pkg: update_packages_rdo
      - pkgrepo: CentOS-PowerTools

{% endif %}
