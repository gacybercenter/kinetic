include:
  - /formulas/nova/install
  - formulas/common/base
  - formulas/common/networking

make_nova_service:
  cmd.script:
    - source: salt://formulas/nova/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        nova_internal_endpoint: {{ pillar ['openstack_services']['nova']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['nova']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['nova']['configuration']['internal_endpoint']['path'] }}
        nova_public_endpoint: {{ pillar ['openstack_services']['nova']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['nova']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['nova']['configuration']['public_endpoint']['path'] }}
        nova_admin_endpoint: {{ pillar ['openstack_services']['nova']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['nova']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['nova']['configuration']['admin_endpoint']['path'] }}
        nova_service_password: {{ pillar ['nova']['nova_service_password'] }}

make_placement_service:
  cmd.script:
    - source: salt://formulas/nova/files/mkservice_placement.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        placement_internal_endpoint: {{ pillar ['openstack_services']['placement']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['placement']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['placement']['configuration']['internal_endpoint']['path'] }}
        placement_public_endpoint: {{ pillar ['openstack_services']['placement']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['placement']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['placement']['configuration']['public_endpoint']['path'] }}
        placement_admin_endpoint: {{ pillar ['openstack_services']['placement']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['placement']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['placement']['configuration']['admin_endpoint']['path'] }}
        placement_service_password: {{ pillar ['placement']['placement_service_password'] }}

/etc/nova/nova.conf:
  file.managed:
    - source: salt://formulas/nova/files/nova.conf
    - template: jinja
    - defaults:
        api_sql_connection_string: 'connection = mysql+pymysql://nova:{{ pillar['nova_password'] }}@{{ pillar ['mysql_configuration']['address'] }}/nova_api'
        sql_connection_string: 'connection = mysql+pymysql://nova:{{ pillar['nova_password'] }}@{{ pillar ['mysql_configuration']['address'] }}/nova'
        transport_url: transport_url = rabbit://openstack:{{ pillar['rmq_openstack_password'] }}@10.10.6.230
        www_authenticate_uri: www_authenticate_uri = {{ pillar['keystone_configuration']['public_endpoint']['protocol'] }}{{ pillar['keystone_configuration']['public_endpoint']['url'] }}{{ pillar['keystone_configuration']['public_endpoint']['port'] }}{{ pillar['keystone_configuration']['public_endpoint']['path'] }}
        auth_url: auth_url = {{ pillar['keystone_configuration']['internal_endpoint']['protocol'] }}{{ pillar['keystone_configuration']['internal_endpoint']['url'] }}{{ pillar['keystone_configuration']['internal_endpoint']['port'] }}{{ pillar['keystone_configuration']['internal_endpoint']['path'] }}
        memcached_servers: memcached_servers = {{ pillar['memcached_servers']['address'] }}:11211
        memcache_servers: memcache_servers = {{ pillar['memcached_servers']['address'] }}:11211
        password: password = {{ pillar['nova_service_password'] }}
        my_ip: my_ip = {{ grains['ipv4'][0] }}
        api_servers: api_servers = {{ pillar['glance_configuration']['internal_endpoint']['protocol'] }}{{ pillar['glance_configuration']['internal_endpoint']['url'] }}{{ pillar['glance_configuration']['internal_endpoint']['port'] }}{{ pillar['glance_configuration']['internal_endpoint']['path'] }}
        neutron_url: url = {{ pillar['neutron_configuration']['internal_endpoint']['protocol'] }}{{ pillar['neutron_configuration']['internal_endpoint']['url'] }}{{ pillar['neutron_configuration']['internal_endpoint']['port'] }}{{ pillar['neutron_configuration']['internal_endpoint']['path'] }}
        metadata_proxy_shared_secret: metadata_proxy_shared_secret = {{ pillar['metadata_secret'] }}
        neutron_password: password = {{ pillar['neutron_service_password'] }}
        placement_password: password = {{ pillar['placement_service_password'] }}

nova_api_service:
  service.running:
    - name: nova-api
    - watch:
      - file: /etc/nova/nova.conf

nova_consoleauth_service:
  service.running:
    - name: nova-consoleauth
    - watch:
      - file: /etc/nova/nova.conf

nova_scheduler_service:
  service.running:
    - name: nova-scheduler
    - watch:
      - file: /etc/nova/nova.conf

nova_conductor_service:
  service.running:
    - name: nova-conductor
    - watch:
      - file: /etc/nova/nova.conf

nova_placement_api_service:
  service.running:
    - name: apache2
    - watch:
      - file: /etc/nova/nova.conf

nova-spiceproxy_service:
  service.running:
    - name: nova-spiceproxy
    - enable: True
    - requires:
      - nova-spiceproxy
    - watch:
      - file: /etc/nova/nova.conf
