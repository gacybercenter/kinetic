## Copyright 2020 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

{% if grains['os_family'] == 'Debian' %}

uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - Yoga
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu focal-updates/yoga main
    - file: /etc/apt/sources.list.d/cloudarchive-yoga.list
    - keyid: EC4926EA
    - keyserver: keyserver.ubuntu.com

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
    - dist_upgrade: True

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
    - name: centos-release-openstack-yoga

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
