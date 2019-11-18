include:
  - formulas/common/base
  - formulas/common/networking
  - formulas/storage/install
  - formulas/ceph/common/configure

/etc/ceph/ceph.client.admin.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-admin-keyring
    - prereq:
      - cmd: make_crush_bucket

make_crush_bucket:
  cmd.run:
    - name: ceph osd crush add-bucket {{ grains['host'] }} host && touch /etc/ceph/bucket_done
    - require:
      - sls: formulas/ceph/common/configure
    - creates: /etc/ceph/bucket_done

align_crush_bucket:
  cmd.run:
    - name: ceph osd crush move {{ grains['host'] }} root=default
    - require:
      - sls: formulas/ceph/common/configure
      - cmd: make_crush_bucket
    - onchanges:
      - cmd: make_crush_bucket

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
    - name: __slot__:salt:cmd.shell("ceph-volume inventory --format json-pretty | jq -r '.[] | .sys_api | select(.model=='foo')'") # \'.[] | .sys_api | select(.model=="{{ device }}") | select(.locked==0) | .path\' | sed '{{ loop.index }}p'")
  {% endfor %}
{% endfor %}

db_vg:
  lvm.vg_present:
    - devices:
{% for device in pillar['osd_mappings'][grains['type']]['journals'] %}
  {% for qty in range(pillar['osd_mappings'][grains['type']]['journals'][device]['qty']) %}
        __slot__:salt:cmd.shell("head -n 1 '/etc/ceph/journals/{{ device }}/{{ loop.index }}'")
  {% endfor %}
{% endfor %}

{% for osd in range(pillar['osd_mappings'][grains['type']]['osd'] | length) %}
  {% set step = 100 // pillar['osd_mappings'][grains['type']]['osd'] | length %}
db_lv_{{ osd }}:
  lvm.lv_present:
    - vgname: db_vg
    - extents: {{ step }}%VG
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
      - sls: formulas/ceph/common/configure
      - lvm: db_lv_{{ loop.index0 }}
{% endfor %}
