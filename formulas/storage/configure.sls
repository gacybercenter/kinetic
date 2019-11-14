include:
  - formulas/common/base
  - formulas/common/networking
  - formulas/storage/install
  - formulas/ceph/common/configure

/etc/ceph/ceph.client.admin.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-admin-keyring

/var/lib/ceph/bootstrap-osd/ceph.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-keyring

ceph osd crush add-bucket {{ grains['host'] }} host:
  cmd.run:
    - require:
      - sls: formulas/ceph/common/configure

ceph osd crush move {{ grains['host'] }} root=default:
  cmd.run:
    - require:
      - sls: formulas/ceph/common/configure

{% for device in pillar['osd_mappings'][grains['type']]['journal'] %}
{% set disk = salt.cmd.shell('lsblk -p -n --output name,model | grep "'+device+'" | cut -d" " -f1') %}
db_pv:
  lvm.pv_present:
    - name: {{ disk }}

db_vg:
  lvm.vg_present:
    - devices: {{ disk }}

db_lv:
  lvm.lv_present:
    - vgname: db_vg
    - size: 100%FREE
{% endfor %}

{% for osd in range(pillar['osd_mappings'][grains['type']]['osd'] | length) %}
  {% set step = 100 // pillar['osd_mappings'][grains['type']]['osd'] | length %}
  {% set start = osd * step %}
  {% set end = start + step %}
journal_mkpart_{{ osd }}:
  module.run:
    - name: partition.mkpart
    - device: /dev/db_vg/db_lv
    - part_type: primary
    - fs_type: ext2
    - start: {{ start }}%
    - end: {{ end }}%
    - unless:
      - parted -s -m /dev/db_vg/db_lv print {{ osd + 1 }} 2>>/dev/null
{% endfor %}

{% for osd in pillar['osd_mappings'][grains['type']]['osd'] %}
initial_zap_osd_{{ osd }}:
  cmd.run:
    - name: wipefs -fa {{ osd }} && dd if=/dev/zero of={{ osd }} bs=1M count=100
    - prereq:
      - cmd: create_osd_{{ osd }}

create_osd_{{ osd }}:
  cmd.run:
    - name: ceph-volume lvm create --bluestore --data {{ osd }}
    - unless:
      - vgdisplay --verbose | grep -q {{ osd }}
    - require:
      - sls: formulas/ceph/common/configure
{% endfor %}
