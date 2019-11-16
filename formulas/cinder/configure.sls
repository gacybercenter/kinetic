include:
  - formulas/cinder/install
  - formulas/common/base
  - formulas/common/networking
  - formulas/ceph/common/configure

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

make_cinder_pool:
  event.send:
    - name: create/{{ grains['type'] }}/pool
    - data:
        pgs: {{ pillar['cephconf']['volumes_pgs'] }}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/ceph/ceph.client.volumes.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-volumes-keyring
    - mode: 640
    - user: root
    - group: cinder

/etc/cinder/cinder.conf:
  file.managed:
    - source: salt://formulas/cinder/files/cinder.conf
    - template: jinja
    - defaults:
{% for server, addresses in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        sql_connection_string: 'connection = mysql+pymysql://cinder:{{ pillar['cinder']['cinder_mysql_password'] }}@{{ address }}/cinder'
    {%- endif -%}
  {%- endfor -%}
{% endfor %}
{% for server, addresses in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address }}
    {%- endif -%}
  {%- endfor -%}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['cinder']['cinder_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}

cinder_api_service:
  service.running:
{% if grains['os_family'] == 'Debian'}
    - name: apache2
{% elif grains['os_family'] == 'RedHat'}
    - name: httpd
{% endif %}
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf

cinder_scheduler_service:
  service.running:
    - name: cinder-scheduler
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf

cinder_volume_service:
  service.running:
    - name: cinder-volume
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf
