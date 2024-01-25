## Copyright 2018 Augusta University
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
  - /formulas/common/fluentd/configure
  - /formulas/common/ceph/configure

get_adminkey:
  file.managed:
    - name: /etc/ceph/ceph.client.admin.keyring
    - contents_pillar: ceph:ceph-client-admin-keyring
    - mode: "0644"
    - user: root
    - group: root
    - prereq:
      - cmd: add_crush_bucket

add_crush_bucket:
  cmd.run:
    - name: ceph osd crush add-bucket {{ grains['host'] }} host
    - require_in:
      - cmd: move_crush_bucket
    - creates:
      - /etc/ceph/bucket_done

move_crush_bucket:
  cmd.run:
    - name: ceph osd crush move {{ grains['host'] }} root=default
    - require_in:
      - file: finish_crush_bucket
    - creates:
      - /etc/ceph/bucket_done

finish_crush_bucket:
  file.managed:
    - name: /etc/ceph/bucket_done

wipe_adminkey:
  file.absent:
    - name: /etc/ceph/ceph.client.admin.keyring

/var/lib/ceph/bootstrap-osd/ceph.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-keyring

## Journal Creation
## Read in the model and respective quantities of each disk
## identified to be a journal in the pillar (see environmen/osd_mappings in your pillar)
## This section will identify unused disks of the correct model in the correct quantity,
## create a pv, and write a unique single-line file with the path to the device
## in /etc/ceph/journals/( model of device)/(number representing order in which it was made into a pv)
## if in your pillar you specify:
##
## journals:
##   foomodel:
##     qty: 3
##   barmodel:
##     qty: 2
##
##This section will create /etc/ceph/journals/foomodel/[1-3] and /etc/ceph/journals/barmodel/[1-2], with the contents of each file being /dev/path/to/disk
## on line 1

{% for device in pillar['osd_mappings'][grains['type']]['journals'] %}
  {% for qty in range(pillar['osd_mappings'][grains['type']]['journals'][device]['qty']) %}
db_pv_{{ device }}_{{ loop.index }}:
  lvm.pv_present:
    - name: __slot__:salt:cmd.shell("ceph-volume inventory --format json | jq -r '.[] | .sys_api | select(.model==\"{{ device }}\") | select(.locked==0) | .path' | sed -n '{{ loop.index }}p'")
    - unless:
      - test -d /dev/db_vg
    - require:
      - sls: /formulas/storage/install
  {% endfor %}
{% endfor %}

db_vg:
  lvm.vg_present:
    - unless:
       - test -d /dev/db_vg
    - require:
      - sls: /formulas/storage/install
    - devices:
{% for device in pillar['osd_mappings'][grains['type']]['journals'] %}
  {% for qty in range(pillar['osd_mappings'][grains['type']]['journals'][device]['qty']) %}
      - {{ salt['cmd.shell']("ceph-volume inventory --format json | jq -r '.[] | .sys_api | select(.model==\""+device+"\") | select(.locked==0) | .path' | sed -n '"+loop.index|string+"p'") }}
  {% endfor %}
{% endfor %}

{% for osd in range(pillar['osd_mappings'][grains['type']]['osd'] | length) %}
  {% set step = 100 // pillar['osd_mappings'][grains['type']]['osd'] | length %}
db_lv_{{ osd }}:
  lvm.lv_present:
    - vgname: db_vg
    - extents: {{ step }}%VG
    - force: True
{% endfor %}

{% for osd in pillar['osd_mappings'][grains['type']]['osd'] %}
initial_zap_osd_{{ osd }}:
  cmd.run:
    - name: ceph-volume lvm zap --destroy {{ osd }}
    - prereq:
      - cmd: create_osd_{{ osd }}

create_osd_{{ osd }}:
  cmd.run:
    - name: ceph-volume lvm create --bluestore --data {{ osd }} --block.db db_vg/db_lv_{{ loop.index0 }}
    - unless:
      - vgdisplay --verbose | grep -q {{ osd }}
    - require:
      - sls: /formulas/common/ceph/configure
      - lvm: db_lv_{{ loop.index0 }}
{% endfor %}
