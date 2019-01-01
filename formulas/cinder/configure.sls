include:
  - /formulas/cinder/install
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

/etc/ceph/ceph.client.volumes.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-volumes-keyring
    - mode: 640
    - user: root
    - group: cinder

make_cinder_service:
  cmd.script:
    - source: salt://formulas/cinder/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        cinder_internal_endpoint_v2: {{ pillar ['openstack_services']['cinder']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['cinder']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['cinder']['configuration']['internal_endpoint']['v2_path'] }}
        cinder_public_endpoint_v2: {{ pillar ['openstack_services']['cinder']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['cinder']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['cinder']['configuration']['public_endpoint']['v2_path'] }}
        cinder_admin_endpoint_v2: {{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['v2_path'] }}
        cinder_internal_endpoint_v3: {{ pillar ['openstack_services']['cinder']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['cinder']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['cinder']['configuration']['internal_endpoint']['v3_path'] }}
        cinder_public_endpoint_v3: {{ pillar ['openstack_services']['cinder']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['cinder']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['cinder']['configuration']['public_endpoint']['v3_path'] }}
        cinder_admin_endpoint_v: {{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['v3_path'] }}
        cinder_service_password: {{ pillar ['cinder']['cinder_service_password'] }}

/etc/cinder/cinder.conf:
  file.managed:
    - source: salt://formulas/cinder/files/cinder.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://cinder:{{ pillar['cinder']['cinder_mysql_password'] }}@{{ address[0] }}/cinder'
{% endfor %}
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['cinder']['cinder_service_password'] }}
        my_ip: {{ grains['ipv4'][0] }}
        api_servers: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}

/bin/sh -c "cinder-manage db_sync" cinder:
  cmd.run

cinder_api_service:
  service.running:
    - name: apache2
    - watch:
      - file: /etc/cinder/cinder.conf

cinder_scheduler_service:
  service.running:
    - name: cinder-scheduler
    - watch:
      - file: /etc/cinder/cinder.conf

cinder_volume_service:
  service.running:
    - name: cinder-volume
    - watch:
      - file: /etc/cinder/cinder.conf
