include:
  - formulas/zuncompute/install
  - formulas/common/base
  - formulas/common/networking

/etc/zun/zun.conf:
  file.managed:
    - source: salt://formulas/zuncompute/files/zun.conf
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
        my_ip: my_ip = {{ grains['ipv4'][0] }}
        docker_ip: docker_remote_api_host = {{ grains['ipv4'][0] }}
{% for host, address in salt['mine.get']('type:zun', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        etcd_host: etcd_host = {{ host }}
{% endfor %}

/etc/kuryr/kuryr.conf:
  file.managed:
    - source: salt://formulas/zuncompute/files/kuryr.conf
    - template: jinja
    - defaults:
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        password: password = {{ pillar ['zun']['kuryr_service_password'] }}

/etc/sudoers.d/zun_sudoers:
  file.managed:
    - source: salt://formulas/zuncompute/files/zun_sudoers
    - requires:
      - /formulas/zuncompute/install

/etc/zun/rootwrap.d/zun.filters:
  file.managed:
    - source: salt://formulas/zuncompute/files/zun.filters
    - requires:
      - /formulas/zuncompute/install

/etc/systemd/system/docker.service.d/docker.conf:
  file.managed:
    - source: salt://formulas/zuncompute/files/docker.conf
    - makedirs: True
    - template: jinja
    - defaults:
        etcd_url: {{ pillar['endpoints']['internal'] }}
    - requires:
      - /formulas/zuncompute/install

/etc/zun/rootwrap.conf:
  file.managed:
    - source: salt://formulas/zuncompute/files/rootwrap.conf
    - requires:
      - /formulas/zuncompute/install

/etc/systemd/system/zun-compute.service:
  file.managed:
    - source: salt://formulas/zuncompute/files/zun-compute.service
    - requires:
      - /formulas/zuncompute/install

/etc/systemd/system/kuryr-libnetwork.service:
  file.managed:
    - source: salt://formulas/zuncompute/files/kuryr-libnetwork.service
    - requires:
      - /formulas/zuncompute/install

systemctl daemon-reload:
  cmd.wait:
    - watch:
      - file: /etc/systemd/system/docker.service.d/docker.conf

docker_service:
  service.running:
    - name: docker
    - watch:
      - file: /etc/systemd/system/docker.service.d/docker.conf

kuryr_libnetwork_service:
  service.running:
    - name: kuryr-libnetwork
    - watch:
      - file: /etc/kuryr/kuryr.conf

zun_compute_service:
  service.running:
    - name: zun-compute
    - watch:
      - file: /etc/zun/zun.conf
