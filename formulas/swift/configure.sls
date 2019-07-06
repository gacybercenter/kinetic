include:
  - formulas/swift/install
  - formulas/common/base
  - formulas/common/networking
  - formulas/ceph/common/configure

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

/etc/ceph/ceph.client.admin.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-admin-keyring
    - mode: 600
    - user: root
    - group: root

ceph_user_exists:
  user.present:
    - name: ceph
    - home: /etc/ceph

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

ceph auth get-or-create client.swift.{{ grains['id'] }} osd 'allow rwx' mon 'allow rwx' -o /etc/ceph/ceph.client.{{ grains['id'] }}.keyring:
  cmd.run:
    - creates:
      - /etc/ceph/ceph.client.{{ grains['id'] }}.keyring

radosgw_service:
  service.running:
    - name: radosgw
    - enable: true
    - watch:
      - file: /etc/ceph/ceph.conf
