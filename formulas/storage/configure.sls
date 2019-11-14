include:
  - formulas/storage/install
  - formulas/common/base
  - formulas/common/networking
  - formulas/ceph/common/configure

/etc/ceph/ceph.client.admin.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-admin-keyring

{% if grains['os_family'] == 'Debian' %}
/var/lib/ceph/bootstrap-osd/ceph.keyring:
{% elif grains['os_family'] == 'RedHat' %}
/etc/ceph/ceph.client.bootstrap-osd.keyring:
{% endif %}
  file.managed:
    - contents_pillar: ceph:ceph-keyring

ceph osd crush add-bucket {{ grains['host'] }} host:
  cmd.run

ceph osd crush move {{ grains['host'] }} root=default:
  cmd.run

db_array:
  raid.present:
    - name: /dev/md/db_array
    - level: 0
    - devices:
{% for device in pillar['osd_mappings'][grains['type']]['journal'] %}
{% set disk = salt['cmd.run']('lsblk -p -n --output name,model | grep "device" | awk '{ print $1 }'') %}
      - {{ disk }}
{% endfor %}
    - chunk: 512
    - run: true
    - force: true

journal_partition:
  module.run:
    - name: partition.mklabel
    - device: /dev/md/db_array
    - label_type: gpt
    - unless:
      - parted -s -m /dev/md/db_array print 2>>/dev/null

{% for osd in range(pillar['osd_mappings'][grains['type']]['osd'] | length) %}
  {% set step = 100 // pillar['osd_mappings'][grains['type']]['osd'] | length %}
  {% set start = osd * step %}
  {% set end = start + step %}
journal_mkpart_{{ osd }}:
  module.run:
    - name: partition.mkpart
    - device: /dev/md/db_array
    - part_type: primary
    - fs_type: ext2
    - start: {{ start }}%
    - end: {{ end }}%
    - unless:
      - parted -s -m /dev/md/db_array print {{ osd + 1 }} 2>>/dev/null
{% endfor %}

{% for osd in pillar['osd_mappings'][grains['type']]['osd'] %}
initial_zap_osd_{{ osd }}:
  cmd.run:
    - name: ceph-volume lvm zap --destroy {{ osd }}
    - prereq:
      - cmd: create_osd_{{ osd }}

create_osd_{{ osd }}:
  cmd.run:
    - name: ceph-volume lvm create --bluestore --data {{ osd }} --block.db /dev/md/db_array{{loop.index}}
    - unless:
      - vgdisplay --verbose | grep -q {{ osd }}
{% endfor %}
