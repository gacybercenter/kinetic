include:
  - /formulas/{{ grains['role'] }}/install

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
      - nova-manage api_db version | grep -q 72

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
      - nova-manage db version | grep -q 407

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

/etc/nova/nova.conf:
  file.managed:
    - source: salt://formulas/nova/files/nova.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://nova:{{ pillar['nova']['nova_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/nova'
        api_sql_connection_string: 'connection = mysql+pymysql://nova:{{ pillar['nova']['nova_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/nova_api'
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
        password: {{ pillar['nova']['nova_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}
        neutron_password: {{ pillar['neutron']['neutron_service_password'] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        console_domain: {{ pillar['haproxy']['console_domain'] }}
        token_ttl: {{ pillar['nova']['token_ttl'] }}

{% if grains['os_family'] == 'RedHat' %}
spice-html5:
  git.latest:
    - name: https://github.com/freedesktop/spice-html5.git
    - target: /usr/share/spice-html5
{% endif %}

nova_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-api
{% endif %}
    - enable: true
    - retry:
        attempts: 3
        interval: 10
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
    - retry:
        attempts: 3
        interval: 10
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
    - retry:
        attempts: 3
        interval: 10
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
    - retry:
        attempts: 3
        interval: 10
    - watch:
      - file: /etc/nova/nova.conf
