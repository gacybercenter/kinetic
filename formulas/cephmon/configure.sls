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
          {% for host, address in salt['mine.get']('role:cephmon', 'network.ip_addrs', tgt_type='grain')  %}
          [mon.{{ host }}]
          host = {{ host }}
          mon addr = {{ address[0] }}
          {% endfor %}


foo:
  test.nop
