include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

make_manila_service:
  cmd.script:
    - source: salt://formulas/manila/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        manila_internal_endpoint_v1: {{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['v1_path'] }}
        manila_public_endpoint_v1: {{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['v1_path'] }}
        manila_admin_endpoint_v1: {{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['v1_path'] }}
        manila_internal_endpoint_v2: {{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['v2_path'] }}
        manila_public_endpoint_v2: {{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['v2_path'] }}
        manila_admin_endpoint_v2: {{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['v2_path'] }}
        manila_service_password: {{ pillar ['manila']['manila_service_password'] }}

manila-manage db sync:
  cmd.run:
    - runas: manila
    - require:
      - file: /etc/manila/manila.conf

make_nfs_share_type:
  cmd.script:
    - source: salt://formulas/manila/files/mknfs.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
    - require:
      - service: manila_api_service
      - service: manila_scheduler_service
    - retry:
        attempts: 3
        interval: 10

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

  {% from 'formulas/common/macros/spawn.sls' import check_spawnzero_status with context %}
    {{ check_spawnzero_status(grains['type']) }}

{% endif %}

/var/lib/manila/tmp:
  file.directory:
    - makedirs: true
    - user: manila
    - group: manila

/etc/manila/manila.conf:
  file.managed:
    - source: salt://formulas/manila/files/manila.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://manila:{{ pillar['manila']['manila_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/manila'
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
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
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
        password: {{ pillar['manila']['manila_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

manila_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: manila-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-manila-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/manila/manila.conf

manila_scheduler_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: manila-scheduler
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-manila-scheduler
{% endif %}
    - enable: true
    - watch:
      - file: /etc/manila/manila.conf
