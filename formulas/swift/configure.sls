## Copyright 2019 Augusta University
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

include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/common/fluentd/fluentd
  - /formulas/common/ceph/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/sudoers.d/ceph:
  file.managed:
    - contents:
      - ceph ALL = (root) NOPASSWD:ALL
      - Defaults:ceph !requiretty
    - mode: "0644"

/var/lib/ceph/radosgw/ceph-{{ grains['id'] }}:
  file.directory:
    - user: ceph
    - group: ceph

get_adminkey:
  file.managed:
    - name: /etc/ceph/ceph.client.admin.keyring
    - contents_pillar: ceph:ceph-client-admin-keyring
    - mode: "0600"
    - user: root
    - group: root
    - prereq:
      - cmd: make_{{ grains['id'] }}_swiftkey

make_{{ grains['id'] }}_swiftkey:
  cmd.run:
    - name: ceph auth get-or-create client.{{ grains['id'] }} osd 'allow rwx' mon 'allow rwx' -o /etc/ceph/ceph.client.{{ grains['id'] }}.keyring
    - creates:
      - /etc/ceph/ceph.client.{{ grains['id'] }}.keyring

wipe_adminkey:
  file.absent:
    - name: /etc/ceph/ceph.client.admin.keyring

radosgw_service:
  service.running:
    - name: ceph-radosgw@{{ grains['id'] }}.service
    - enable: true
    - watch:
      - file: /etc/ceph/ceph.conf
