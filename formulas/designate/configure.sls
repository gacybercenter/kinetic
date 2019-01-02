include:
  - /formulas/designate/install
  - formulas/common/base
  - formulas/common/networking

make_designate_service:
  cmd.script:
    - source: salt://formulas/designate/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        designate_internal_endpoint: {{ pillar ['openstack_services']['designate']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['designate']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['designate']['configuration']['internal_endpoint']['path'] }}
        designate_public_endpoint: {{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['path'] }}
        designate_admin_endpoint: {{ pillar ['openstack_services']['designate']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['designate']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['designate']['configuration']['admin_endpoint']['path'] }}
        designate_service_password: {{ pillar ['designate']['designate_service_password'] }}

/etc/designate/designate.conf:
  file.managed:
    - source: salt://formulas/designate/files/designate.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://glance:{{ pillar['glance']['glance_mysql_password'] }}@{{ address[0] }}/glance'
{% endfor %}
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['designate']['designate_service_password'] }}
        listen_api: {{ grains['ipv4'][0] }}:9001
        trustee_domain_admin_password: {{ pillar['designate']['designate_service_password'] }}















/etc/glance/glance-api.conf:
  file.managed:
    - source: salt://formulas/glance/files/glance-api.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://glance:{{ pillar['glance']['glance_mysql_password'] }}@{{ address[0] }}/glance'
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['glance']['glance_service_password'] }}

/etc/glance/glance-registry.conf:
  file.managed:
    - source: salt://formulas/glance/files/glance-registry.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://glance:{{ pillar['glance']['glance_mysql_password'] }}@{{ address[0] }}/glance'
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['glance']['glance_service_password'] }}

/bin/sh -c "glance-manage db_sync" glance:
  cmd.run

glance_registry_service:
  service.running:
    - name: glance-registry
    - watch:
      - file: /etc/glance/glance-registry.conf

glance_api_service:
  service.running:
    - name: glance-api
    - watch:
      - file: /etc/glance/glance-api.conf
