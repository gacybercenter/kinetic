include:
  - /formulas/{{ grains['role'] }}/install

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

/etc/heat/heat.conf:
  file.managed:
    - source: salt://formulas/heat/files/heat.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://heat:{{ pillar['heat']['heat_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/heat'
        transport_url: |-
          rabbit://
          {%- for host, addresses in salt['mine.get']('role:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address }}
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        auth_uri: {{ pillar['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        memcached_servers: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}:11211
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
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
