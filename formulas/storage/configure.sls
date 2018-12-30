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

{% for osd in range(pillar['osd_mappings'][grains['type']]['journal'] | length) %}
echo {{ osd }}:
  cmd.run
{% endfor %}
