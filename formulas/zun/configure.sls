include:
  - formulas/zun/install
  - formulas/common/base
  - formulas/common/networking

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

make_kuryr_service:
  cmd.script:
    - source: salt://formulas/zun/files/mkservice_kuryr.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        kuryr_service_password: {{ pillar ['zun']['kuryr_service_password'] }}

/etc/zun/zun.conf:
  file.managed:
    - source: salt://formulas/zun/files/zun.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://zun:{{ pillar['zun']['zun_mysql_password'] }}@{{ address[0] }}/zun'
{% endfor %}
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        auth_strategy: auth_strategy = keystone
        auth_type: auth_type = password
        auth_version: auth_version = v3
        auth_protocol: auth_protocol = http
        password: {{ pillar['zun']['zun_service_password'] }}
        api: host_ip = {{ grains['ipv4'][0] }}
        wsproxy_host: wsproxy_host = {{ grains['ipv4'][0] }}

/etc/sudoers.d/zun_sudoers:
  file.managed:
    - source: salt://formulas/zun/files/zun_sudoers
    - requires:
      - /formulas/zun/install

/etc/zun/api-paste.ini:
  file.managed:
    - source: salt://formulas/zun/files/api-paste.ini
    - requires:
      - /formulas/zun/install

/etc/systemd/system/zun-api.service:
  file.managed:
    - source: salt://formulas/zun/files/zun-api.service
    - requires:
      - /formulas/zun/install

/etc/systemd/system/zun-wsproxy.service:
  file.managed:
    - source: salt://formulas/zun/files/zun-wsproxy.service
    - requires:
      - /formulas/zun/install

/etc/default/etcd:
  file.managed:
    - source: salt://formulas/zun/files/etcd
    - template: jinja
    - defaults:
        etcd_hosts: |
          {%- for host, address in salt['mine.get']('role:zun', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
          ETCD_INITIAL_CLUSTER="{{ host }}=http://{{ address[0] }}:2380"
          {%- endfor %}
        etcd_name: {{ grains['id'] }}
        etcd_listen: {{ grains['ipv4'][0] }}

etcd_service:
  service.running:
    - name: etcd
    - watch:
      - file: /etc/default/etcd

zun_api_service:
  service.running:
    - name: zun-api
    - watch:
      - file: /etc/zun/zun.conf

zun_wsproxy_service:
  service.running:
    - name: zun-wsproxy
    - watch:
      - file: /etc/zun/zun.conf

su -s /bin/sh -c "zun-db-manage upgrade" zun:
  cmd.run
