include:
  - formulas/heat/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

make_heat_service:
  cmd.script:
    - source: salt://formulas/heat/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        heat_service_password: {{ pillar['heat']['heat_service_password'] }}
        heat_internal_endpoint: {{ pillar['openstack_services']['heat']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['heat']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['heat']['configuration']['internal_endpoint']['path'] }}
        heat_public_endpoint: {{ pillar['openstack_services']['heat']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['heat']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['heat']['configuration']['public_endpoint']['path'] }}
        heat_admin_endpoint: {{ pillar['openstack_services']['heat']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['heat']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['heat']['configuration']['admin_endpoint']['path'] }}
        heat_internal_endpoint_cfn: {{ pillar['openstack_services']['heat']['configuration']['internal_endpoint_cfn']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['heat']['configuration']['internal_endpoint_cfn']['port'] }}{{ pillar ['openstack_services']['heat']['configuration']['internal_endpoint_cfn']['path'] }}
        heat_public_endpoint_cfn: {{ pillar['openstack_services']['heat']['configuration']['public_endpoint_cfn']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['heat']['configuration']['public_endpoint_cfn']['port'] }}{{ pillar ['openstack_services']['heat']['configuration']['public_endpoint_cfn']['path'] }}
        heat_admin_endpoint_cfn: {{ pillar['openstack_services']['heat']['configuration']['admin_endpoint_cfn']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['heat']['configuration']['admin_endpoint_cfn']['port'] }}{{ pillar ['openstack_services']['heat']['configuration']['admin_endpoint_cfn']['path'] }}

heat-manage db_sync:
  cmd.run:
    - runas: heat
    - require:
      - file: /etc/heat/heat.conf

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/heat/heat.conf:
  file.managed:
    - source: salt://formulas/heat/files/heat.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://heat:{{ pillar['heat']['heat_mysql_password'] }}@{{ address[0] }}/heat'
{% endfor %}
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        auth_uri: {{ pillar['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['heat']['heat_service_password'] }}
        clients_keystone_auth_uri: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        ec2_authtoken_auth_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        heat_metadata_server_url: {{ pillar['openstack_services']['heat']['configuration']['internal_endpoint_cfn']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['heat']['configuration']['internal_endpoint_cfn']['port'] }}
        heat_waitcondition_server_url: {{ pillar['openstack_services']['heat']['configuration']['internal_endpoint_cfn']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['heat']['configuration']['internal_endpoint_cfn']['port'] }}{{ pillar ['openstack_services']['heat']['configuration']['internal_endpoint_cfn']['path'] }}/waitcondition

heat_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: heat-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-heat-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/heat/heat.conf

heat_api_cfn_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: heat-api-cfn
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-heat-api-cfn
{% endif %}
    - enable: true
    - watch:
      - file: /etc/heat/heat.conf

heat_engine_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: heat-engine
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-heat-engine
{% endif %}
    - enable: true
    - watch:
      - file: /etc/heat/heat.conf
