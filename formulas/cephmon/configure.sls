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
          {% for host in salt.saltutil.runner('mine.get', tgt='cephmon-f7910a37-b4a1-45a8-9318-08905c6976f8', fun='grains.get') %}
          [mon.{{ host }}]
          host = {{ host }}
          {% endfor %}
foo:
  test.nop
