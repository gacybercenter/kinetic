include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

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
        cinder_admin_endpoint_v3: {{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['cinder']['configuration']['admin_endpoint']['v3_path'] }}
        cinder_service_password: {{ pillar ['cinder']['cinder_service_password'] }}

cinder-manage db sync:
  cmd.run:
    - runas: cinder
    - require:
      - file: /etc/cinder/cinder.conf

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

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

/etc/cinder/cinder.conf:
  file.managed:
    - source: salt://formulas/cinder/files/cinder.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://cinder:{{ pillar['cinder']['cinder_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/cinder'
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
        memcached_servers: |
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}:11211
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        password: {{ pillar['cinder']['cinder_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
        rbd_secret_uuid: {{ pillar['ceph']['volumes-uuid'] }}

cinder_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-cinder-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf

cinder_scheduler_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: cinder-scheduler
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-cinder-scheduler
{% endif %}
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf
