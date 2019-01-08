include:
  - formulas/storage/install
  - formulas/common/base
  - formulas/common/networking

/etc/ceph/ceph.conf:
  file.managed:
    - source: salt://formulas/cephmon/files/ceph.conf
    - template: jinja
    - makedirs: True
    - defaults:
        fsid: {{ pillar['ceph']['fsid'] }}
        mon_members: |
          {% for host, address in salt['mine.get']('role:cephmon', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
          [mon.{{ host }}]
          host = {{ host }}
          mon addr = {{ address[0] }}
          {% endfor %}
        swift_members: |
          {% for host, address in salt['mine.get']('role:swift', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
          [client.swift.{{ host }}]
          host = {{ host }}
          keyring = /etc/ceph/ceph.client.{{ host }}.keyring
          rgw_keystone_url = {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}
          rgw keystone api version = 3
          rgw keystone admin user = keystone
          rgw keystone admin password = {{ pillar ['keystone']['keystone_service_password'] }}
          rgw keystone admin project = service
          rgw keystone admin domain = default
          rgw keystone accepted roles = admin,user
          rgw keystone token cache size = 10
          rgw keystone revocation interval = 300
          rgw keystone implicit tenants = true
          rgw swift account in url = true
          {% endfor %}
        sfe_network: {{ pillar['subnets']['sfe'] }}
        sbe_network: {{ pillar['subnets']['sbe'] }}

/etc/ceph/ceph.client.admin.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-admin-keyring

/var/lib/ceph/bootstrap-osd/ceph.keyring:
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
      - {{ device }}
{% endfor %}
    - chunk: 512
    - run: true

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
    - start: {{ start }}%
    - end: {{ end }}%
    - unless:
      - parted -s -m /dev/md/db_array print {{ osd + 1 }} 2>>/dev/null
{% endfor %}

{% for osd in pillar['osd_mappings'][grains['type']]['osd'] %}
create_osd_{{ osd }}:
  cmd.run:
    - name: ceph-volume lvm create --bluestore --data {{ osd }} --block.db /dev/md/db_array{{loop.index}}
    - unless:
      - vgdisplay --verbose | grep -q {{ osd }}
{% endfor %}

ceph osd pool create vms {{ pillar['cephconf']['vms_pgs'] }}:
  cmd.run:
    - unless:
      - ceph osd pool get vms pg_num | grep -q {{ pillar['cephconf']['vms_pgs'] }}

ceph osd pool create images {{ pillar['cephconf']['images_pgs'] }}:
  cmd.run:
    - unless:
      - ceph osd pool get images pg_num | grep -q {{ pillar['cephconf']['images_pgs'] }}

ceph osd pool create volumes {{ pillar['cephconf']['volumes_pgs'] }}:
  cmd.run:
    - unless:
      - ceph osd pool get volumes pg_num | grep -q {{ pillar['cephconf']['volumes_pgs'] }}
