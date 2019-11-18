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
    - onchanges:
      - cmd: make_crush_bucket
    - require:
      - sls: formulas/ceph/common/configure

remove_admin_keyring:
  file.absent:
    - name: /etc/ceph/ceph.client.admin.keyring
    - onchanges:
      - cmd: align_crush_bucket

/var/lib/ceph/bootstrap-osd/ceph.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-keyring




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
