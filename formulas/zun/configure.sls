include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

zun-db-manage upgrade:
  cmd.run:
    - runas: zun
    - require:
      - file: /etc/zun/zun.conf
    - unless:
      - zun-db-manage version | grep -q e4385cf0e363

make_kuryr_user:
  cmd.script:
    - source: salt://formulas/zun/files/mkuser_kuryr.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        kuryr_service_password: {{ pillar ['zun']['kuryr_service_password'] }}

make_zun_service:
  cmd.script:
    - source: salt://formulas/zun/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        zun_internal_endpoint: {{ pillar ['openstack_services']['zun']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['zun']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['zun']['configuration']['internal_endpoint']['path'] }}
        zun_public_endpoint: {{ pillar ['openstack_services']['zun']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['zun']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['zun']['configuration']['public_endpoint']['path'] }}
        zun_admin_endpoint: {{ pillar ['openstack_services']['zun']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['zun']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['zun']['configuration']['admin_endpoint']['path'] }}
        zun_service_password: {{ pillar ['zun']['zun_service_password'] }}

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

/etc/zun/zun.conf:
  file.managed:
    - source: salt://formulas/zun/files/zun.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://zun:{{ pillar['zun']['zun_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/zun'
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
        auth_strategy: auth_strategy = keystone
        auth_type: auth_type = password
        auth_version: auth_version = v3
        auth_protocol: auth_protocol = https
        password: {{ pillar['zun']['zun_service_password'] }}
        api: host_ip = {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        wsproxy_host: wsproxy_host = {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}

/etc/sudoers.d/zun_sudoers:
  file.managed:
    - source: salt://formulas/zun/files/zun_sudoers
    - requires:
      - /formulas/zun/install

/etc/zun/api-paste.ini:
  file.managed:
    - source: salt://formulas/zun/files/api-paste.ini
    - requires:
      - sls: /formulas/zun/install

/etc/systemd/system/zun-api.service:
  file.managed:
    - source: salt://formulas/zun/files/zun-api.service
    - requires:
      - sls: /formulas/zun/install

/etc/systemd/system/zun-wsproxy.service:
  file.managed:
    - source: salt://formulas/zun/files/zun-wsproxy.service
    - requires:
      - sls: /formulas/zun/install

zun_api_service:
  service.running:
    - name: zun-api
    - enable: true
    - watch:
      - file: /etc/zun/zun.conf

zun_wsproxy_service:
  service.running:
    - name: zun-wsproxy
    - enable: true
    - watch:
      - file: /etc/zun/zun.conf
