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
    - humanname: Ubuntu Cloud Archive - Antelope
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu jammy-updates/antelope main
    - file: /etc/apt/sources.list.d/cloudarchive-antelope.list
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
crb:
  pkgrepo.managed:
    - humanname: crb
    - name: crb
    - baseurl: https://download.rockylinux.org/pub/rocky/9/CRB/x86_64/os/
    - gpgcheck: 1
    - enabled: 1
    - gpgkey: https://download.rockylinux.org/pub/rocky/9/RPM-GPG-KEY-rockylinux-release

crb-install:
  pkg.installed:
    - name: powertools

rdo:
  pkg.installed:
    - name: centos-release-openstack-antelope

update_packages_rdo:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkg: rdo
      - pkgrepo: crb

openstack-selinux:
  pkg.installed:
    - require:
      - pkg: rdo
      - pkg: update_packages_rdo
      - pkgrepo: crb

{% endif %}
