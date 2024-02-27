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

ceph_repo:
  pkgrepo.managed:
    - humanname: Ceph Quincy
    - name: deb https://download.ceph.com/debian-quincy {{ pillar['ubuntu']['name'] }} main
    - file: /etc/apt/sources.list.d/ceph.list
    - key_url: https://download.ceph.com/keys/release.asc

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - ceph_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

ceph_repo:
  pkgrepo.managed:
    - name: ceph
    - baseurl: https://download.ceph.com/rpm-quincy/el9/noarch
    - file: /etc/yum.repos.d/ceph.repo
    - gpgkey: https://download.ceph.com/keys/release.asc

ceph_repo_noarch:
  pkgrepo.managed:
    - name: ceph_noarch
    - baseurl: https://download.ceph.com/rpm-quincy/el9/noarch
    - file: /etc/yum.repos.d/ceph_noarch.repo
    - gpgkey: https://download.ceph.com/keys/release.asc

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: ceph_repo
      - pkgrepo: ceph_repo_noarch

{% endif %}
