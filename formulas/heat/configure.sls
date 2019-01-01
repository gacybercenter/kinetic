include:
  - /formulas/glance/install
  - formulas/common/base
  - formulas/common/networking

make_heat_service:
  cmd.script:
    - source: salt://apps/openstack/heat/files/mkservice.sh
    - template: jinja
    - defaults:
        os_password: {{ pillar['openstack']['openstack_admin_pass'] }}
        os_auth_url: {{ pillar['keystone_configuration']['internal_endpoint']['protocol'] }}{{ pillar['keystone_configuration']['internal_endpoint']['url'] }}{{ pillar['keystone_configuration']['internal_endpoint']['port'] }}{{ pillar['keystone_configuration']['internal_endpoint']['path'] }}
        heat_service_password: {{ pillar['heat']['heat_service_password'] }}
        heat_public_endpoint: {{ pillar['heat_configuration']['public_endpoint']['protocol'] }}{{ pillar['heat_configuration']['public_endpoint']['url'] }}{{ pillar['heat_configuration']['public_endpoint']['port'] }}{{ pillar['heat_configuration']['public_endpoint']['path'] }}
        heat_internal_endpoint: {{ pillar['heat_configuration']['internal_endpoint']['protocol'] }}{{ pillar['heat_configuration']['internal_endpoint']['url'] }}{{ pillar['heat_configuration']['internal_endpoint']['port'] }}{{ pillar['heat_configuration']['internal_endpoint']['path'] }}
        heat_admin_endpoint: {{ pillar['heat_configuration']['admin_endpoint']['protocol'] }}{{ pillar['heat_configuration']['admin_endpoint']['url'] }}{{ pillar['heat_configuration']['admin_endpoint']['port'] }}{{ pillar['heat_configuration']['admin_endpoint']['path'] }}
        heat_public_endpoint_cfn: {{ pillar['heat_configuration']['public_endpoint_cfn']['protocol'] }}{{ pillar['heat_configuration']['public_endpoint_cfn']['url'] }}{{ pillar['heat_configuration']['public_endpoint_cfn']['port'] }}{{ pillar['heat_configuration']['public_endpoint_cfn']['path'] }}
        heat_internal_endpoint_cfn: {{ pillar['heat_configuration']['internal_endpoint_cfn']['protocol'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['url'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['port'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['path'] }}
        heat_admin_endpoint_cfn: {{ pillar['heat_configuration']['admin_endpoint_cfn']['protocol'] }}{{ pillar['heat_configuration']['admin_endpoint_cfn']['url'] }}{{ pillar['heat_configuration']['admin_endpoint_cfn']['port'] }}{{ pillar['heat_configuration']['admin_endpoint_cfn']['path'] }}

/etc/heat/heat.conf:
  file.managed:
    - source: salt://apps/openstack/heat/files/heat.conf
    - source_hash: salt://apps/openstack/heat/files/hash
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://heat:{{ pillar['heat_password'] }}@{{ pillar ['mysql_configuration']['address'] }}/heat'
        transport_url: transport_url = rabbit://openstack:{{ pillar['rmq_openstack_password'] }}@10.10.6.230
        auth_strategy: auth_strategy = keystone
        auth_uri: auth_uri = {{ pillar['keystone_configuration']['public_endpoint']['protocol'] }}{{ pillar['keystone_configuration']['public_endpoint']['url'] }}{{ pillar['keystone_configuration']['public_endpoint']['port'] }}{{ pillar['keystone_configuration']['public_endpoint']['path'] }}
        auth_url: auth_url = {{ pillar['keystone_configuration']['internal_endpoint']['protocol'] }}{{ pillar['keystone_configuration']['internal_endpoint']['url'] }}{{ pillar['keystone_configuration']['internal_endpoint']['port'] }}{{ pillar['keystone_configuration']['internal_endpoint']['path'] }}
        memcached_servers: memcached_servers = {{ pillar['memcached_servers']['address'] }}:11211
        auth_type: auth_type = password
        project_domain_name: project_domain_name = {{ pillar['heat_openrc']['OS_PROJECT_DOMAIN_NAME'] }}
        user_domain_name: user_domain_name = {{ pillar['heat_openrc']['OS_USER_DOMAIN_NAME'] }}
        project_name: project_name = {{ pillar['heat_openrc']['OS_PROJECT_NAME'] }}
        username: username = {{ pillar['heat_openrc']['OS_USERNAME'] }}
        password: password = {{ pillar['heat_service_password'] }}
        clients_keystone_auth_uri: auth_uri = {{ pillar['keystone_configuration']['internal_endpoint']['protocol'] }}{{ pillar['keystone_configuration']['internal_endpoint']['url'] }}{{ pillar['keystone_configuration']['internal_endpoint']['port'] }}{{ pillar['keystone_configuration']['internal_endpoint']['path'] }}
        ec2_authtoken_auth_uri: auth_uri = {{ pillar['keystone_configuration']['public_endpoint']['protocol'] }}{{ pillar['keystone_configuration']['public_endpoint']['url'] }}{{ pillar['keystone_configuration']['public_endpoint']['port'] }}{{ pillar['keystone_configuration']['public_endpoint']['path'] }}
        heat_metadata_server_url: heat_metadata_server_url = {{ pillar['heat_configuration']['internal_endpoint_cfn']['protocol'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['url'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['port'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['path'] }}
        heat_waitcondition_server_url: heat_waitcondition_server_url = {{ pillar['heat_configuration']['internal_endpoint_cfn']['protocol'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['url'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['port'] }}{{ pillar['heat_configuration']['internal_endpoint_cfn']['path'] }}/waitcondition
        stack_domain_admin: stack_domain_admin = heat_domain_admin
        stack_domain_admin_password: stack_domain_admin_password = {{ pillar['heat_service_password'] }}
        stack_user_domain_name: stack_user_domain_name = {{ pillar['heat_openrc']['OS_USERNAME'] }}

/bin/sh -c "heat-manage db_sync" heat:
  cmd.run

heat_api_service:
  service.running:
    - name: heat-api
    - watch:
      - file: /etc/heat/heat.conf

heat_api_cfn_service:
  service.running:
    - name: heat-api-cfn
    - watch:
      - file: /etc/heat/heat.conf

heat_engine_service:
  service.running:
    - name: heat-engine
    - watch:
      - file: /etc/heat/heat.conf
