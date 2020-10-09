include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/ceph/common/configure

{% if grains['spawning'] == 0 %}

make_swift_service:
  cmd.script:
    - source: salt://formulas/swift/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        swift_service_password: {{ pillar ['swift']['swift_service_password'] }}
        swift_public_endpoint: {{ pillar ['openstack_services']['swift']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['swift']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['swift']['configuration']['public_endpoint']['path'] }}
        swift_internal_endpoint: {{ pillar ['openstack_services']['swift']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['swift']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['swift']['configuration']['internal_endpoint']['path'] }}
        swift_admin_endpoint: {{ pillar ['openstack_services']['swift']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['swift']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['swift']['configuration']['admin_endpoint']['path'] }}

spawnzero_complete:
  grains.present:
    - value: True
  module.run:
    - name: mine.send
    - m_name: spawnzero_complete
    - kwargs:
        mine_function: grains.item
    - args:
      - spawnzero_complete
    - onchanges:
      - grains: spawnzero_complete

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endif %}

/etc/sudoers.d/ceph:
  file.managed:
    - contents:
      - ceph ALL = (root) NOPASSWD:ALL
      - Defaults:ceph !requiretty
    - mode: 644

/var/lib/ceph/radosgw/ceph-{{ grains['id'] }}:
  file.directory:
    - user: ceph
    - group: ceph

get_adminkey:
  file.managed:
    - name: /etc/ceph/ceph.client.admin.keyring
    - contents_pillar: ceph:ceph-client-admin-keyring
    - mode: 600
    - user: root
    - group: root
    - prereq:
      - cmd: make_{{ grains['id'] }}_swiftkey

make_{{ grains['id'] }}_swiftkey:
  cmd.run:
    - name: ceph auth get-or-create client.{{ grains['id'] }} osd 'allow rwx' mon 'allow rwx' -o /etc/ceph/ceph.client.{{ grains['id'] }}.keyring
    - creates:
      - /etc/ceph/ceph.client.{{ grains['id'] }}.keyring

wipe_adminkey:
  file.absent:
    - name: /etc/ceph/ceph.client.admin.keyring

radosgw_service:
  service.running:
    - name: ceph-radosgw@{{ grains['id'] }}.service
    - enable: true
    - watch:
      - file: /etc/ceph/ceph.conf
