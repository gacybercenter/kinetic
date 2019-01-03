include:
  - /formulas/nova/install
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

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."
    - onchanges:
      - cmd: neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head

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
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcache_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['nova']['nova_service_password'] }}
        my_ip: {{ grains['ipv4'][0] }}
        api_servers: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
        neutron_url: {{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['path'] }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}
        neutron_password: {{ pillar['neutron']['neutron_service_password'] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        console_domain: {{ pillar['haproxy']['console_domain'] }}

su -s /bin/sh -c "nova-manage api_db sync" nova:
  cmd.run:
    - unless:
      - nova-manage api_db version | grep -q 61

su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova:
  cmd.run:
    - unless:
      - nova-manage cell_v2 list_cells | grep -q cell0

su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova:
  cmd.run:
    - unless:
      - nova-manage cell_v2 list_cells | grep -q cell1

su -s /bin/sh -c "nova-manage db sync" nova:
  cmd.run:
    - unless:
      - nova-manage db version | grep -q 390

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
{% endfor %}
