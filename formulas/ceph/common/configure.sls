/etc/ceph/ceph.conf:
  file.managed:
    - source: salt://formulas/ceph/common/files/ceph.conf
    - template: jinja
    - makedirs: True
    - defaults:
        fsid: {{ pillar['ceph']['fsid'] }}
        mon_global: |
          mon host = [v2:10.120.5.99:3300,v1:10.120.5.99:6789],[v2:10.120.5.100:3300,v1:10.120.5.100:6789],[v2:10.120.5.101:3300,v1:10.120.5.101:6789]
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
