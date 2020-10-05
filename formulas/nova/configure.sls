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

update_cells:
  cmd.run:
    - name: nova-manage cell_v2 list_cells | grep cell1 | cut -d" " -f4 | while read uuid;do nova-manage cell_v2 update_cell --cell_uuid $uuid;done
    - onchanges:
      - file: /etc/nova/nova.conf
    - watch_in:
      - service: nova_api_service
      - service: nova_scheduler_service
      - service: nova_conductor_service
      - service: nova_spiceproxy_service

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

## This is lightning fast but I'm not sure how I feel about writing directly to the database
## outside the context of the API.  Should probably change to the flavor_present state
## once the openstack-ng modules are done in salt
{% for flavor, attribs in pillar['flavors'].items() if salt['mysql.query']('nova_api', "select * from flavors where name='"+flavor+"'", connection_host=pillar['haproxy']['dashboard_domain'],connection_user='nova',connection_pass=pillar['nova']['nova_mysql_password'])['rows returned'] == 0 %}
create_{{ flavor }}:
  mysql_query.run:
    - database: nova_api
    - connection_pass: {{ pillar['nova']['nova_mysql_password'] }}
    - connection_user: nova
    - connection_host: {{ pillar['haproxy']['dashboard_domain'] }}
    - query: "INSERT INTO nova_api.flavors(name,memory_mb,vcpus,swap,flavorid,rxtx_factor,root_gb,ephemeral_gb,disabled,is_public) VALUES ('{{ flavor }}',{{ attribs['ram'] }},{{ attribs['vcpus'] }},0,'{{ salt['random.get_str']('64')|uuid }}',1,{{ attribs['disk'] }},0,0,1);"
    - output: "/root/{{ flavor }}"
    - require:
      - service: nova_api_service
      - service: nova_scheduler_service
      - service: nova_conductor_service
      - service: nova_spiceproxy_service
    - retry:
        attempts: 3
        interval: 10
{% endfor %}

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

{% if grains['os_family'] == 'Debian' %}
spice-html5:
  git.latest:
    - name: https://gitlab.com/gacybercenter/spice-html5.git
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

nova_spiceproxy_service:
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
