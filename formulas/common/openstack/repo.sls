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

uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - {{ pillar['openstack']['version'] }}
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu {{ pillar['ubuntu']['name'] }}-updates/{{ pillar['openstack']['version'] }} main
    - file: /etc/apt/sources.list.d/cloudarchive.list
    - keyid: 5EDB1B62EC4926EA
    - keyserver: keyserver.ubuntu.com

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
    - dist_upgrade: True

