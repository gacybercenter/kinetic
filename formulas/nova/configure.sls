include:
  - formulas/nova/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

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

nova-manage api_db sync:
  cmd.run:
    - runas: nova
    - require:
      - file: /etc/nova/nova.conf
    - unless:
      - nova-manage api_db version | grep -q 67

nova-manage cell_v2 map_cell0:
  cmd.run:
    - runas: nova
    - require:
      - file: /etc/nova/nova.conf
    - unless:
      - nova-manage cell_v2 list_cells | grep -q cell0

nova-manage cell_v2 create_cell --name=cell1 --verbose:
  cmd.run:
    - runas: nova
    - require:
      - file: /etc/nova/nova.conf
    - unless:
      - nova-manage cell_v2 list_cells | grep -q cell1

nova-manage db sync:
  cmd.run:
    - runas: nova
    - require:
      - file: /etc/nova/nova.conf
    - unless:
      - nova-manage db version | grep -q 402

/etc/nova/flavors:
  file.directory

{% for flavor_name, args in pillar.get('flavors', {}).items() %}

{{ flavor_name }}_flavor_creation:
  cmd.script:
    - source: salt://formulas/nova/files/flavors.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        vcpus: {{ args['vcpus'] }}
        ram: {{ args['ram'] }}
        disk: {{ args['disk'] }}
        flavor_name: {{ flavor_name }}
    - require:
      - file: /etc/nova/nova.conf
      - service: nova_api_service
    - creates:
      - /etc/nova/flavors/{{ flavor_name }}

{% endfor %}

make_nova_pool:
  event.send:
    - name: create/{{ grains['type'] }}/pool
    - data:
        pgs: {{ pillar['cephconf']['vms_pgs'] }}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/nova/nova.conf:
  file.managed:
    - source: salt://formulas/nova/files/nova.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://nova:{{ pillar['nova']['nova_mysql_password'] }}@{{ address[0] }}/nova'
        api_sql_connection_string: 'connection = mysql+pymysql://nova:{{ pillar['nova']['nova_mysql_password'] }}@{{ address[0] }}/nova_api'
{% endfor %}
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
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
        password: {{ pillar['nova']['nova_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}
        neutron_password: {{ pillar['neutron']['neutron_service_password'] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        console_domain: {{ pillar['haproxy']['console_domain'] }}

nova_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/nova/nova.conf

nova_scheduler_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-scheduler
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-scheduler
{% endif %}
    - enable: true
    - watch:
      - file: /etc/nova/nova.conf

nova_conductor_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-conductor
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-conductor
{% endif %}
    - enable: true
    - watch:
      - file: /etc/nova/nova.conf

nova-spiceproxy_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-spiceproxy
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-spicehtml5proxy
{% endif %}
    - enable: true
    - watch:
      - file: /etc/nova/nova.conf
