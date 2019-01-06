include:
  - formulas/swift/install
  - formulas/common/base
  - formulas/common/networking

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
          rgw_keystone_url = {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
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
    - file_mode: 644

ceph-authtool -C -n client.swift.{{ grains['id'] }} --gen-key /etc/ceph/ceph.client.swift.keyring:
  cmd.run

ceph-authtool -n client.swift.{{ grains['id'] }} --cap mon 'allow rwx' --cap osd 'allow rwx' /etc/ceph/ceph.client.swift.keyring:
  cmd.run

ceph auth add client.swift.{{ grains['id'] }} --in-file=/etc/ceph/ceph.client.swift.keyring:
  cmd.run

radosgw_service:
  service.running:
    - name: radosgw
    - enable: true
    - watch:
      - file: /etc/ceph/ceph.conf
