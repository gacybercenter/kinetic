include:
  - formulas/cephmon/install
  - formulas/common/base
  - formulas/common/networking

mine.update:
  module.run:
      - network.ip_addrs: [ens3]
      - grains.get: [id]

/etc/ceph/ceph.conf:
  file.managed:
    - source: salt://formulas/cephmon/files/ceph.conf
    - template: jinja
    - makedirs: True
    - defaults:
        fsid: changeme
        mon_members: |
          {% for host in salt['mine.get']('role:cephmon', 'grains.get', tgt_type='grain')  %}
          [mon.{{ host }}]
          host = {{ host }}
          {% endfor %}
foo:
  test.nop
