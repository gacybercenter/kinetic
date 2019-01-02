include:
  - /formulas/designate/install
  - formulas/common/base
  - formulas/common/networking

make_designate_service:
  cmd.script:
    - source: salt://formulas/designate/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        designate_public_endpoint: {{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['path'] }}
        designate_service_password: {{ pillar ['designate']['designate_service_password'] }}

/etc/designate/designate.conf:
  file.managed:
    - source: salt://formulas/designate/files/designate.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://designate:{{ pillar['designate']['designate_mysql_password'] }}@{{ address[0] }}/designate'
{% endfor %}
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['designate']['designate_service_password'] }}
        listen_api: {{ grains['ipv4'][0] }}:9001
        designate_public_endpoint: {{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['path'] }}

/etc/designate/tlds.conf:
  file.managed:
    - source: salt://formulas/designate/files/tlds

/etc/bind/named.conf.options:
  file.managed:
    - source: salt://formulas/designate/files/named.conf.options
    - template: jinja
    - defaults:
        public_dns: {{ pillar['subnets']['float_dns'] }}

/etc/designate/pools.yaml:
  file.managed:
    - source: salt://formulas/designate/files/pools.yaml
    - template: jinja
    - defaults:
        hostname: {{ grains['fqdn'] }}.

/etc/bind/rndc.key:
  file.managed:
    - contents_pillar: designate:designate_rndc_key
    - mode: 640
    - user: root
    - group: bind

/bin/sh -c "designate-manage database sync" designate:
  cmd.run:
    - unless:
      - /bin/sh -c "designate-manage database version" designate | grep -q 100

designate_api_service:
  service.running:
    - name: designate-api
    - watch:
      - file: /etc/designate/designate.conf

designate_central_service:
  service.running:
    - name: designate-central
    - watch:
      - file: /etc/designate/designate.conf

designate_worker_service:
  service.running:
    - name: designate-worker
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_producer_service:
  service.running:
    - name: designate-producer
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_mdns_service:
  service.running:
    - name: designate-mdns
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_bind9_service:
  service.running:
    - name: bind9
    - watch:
      - file: /etc/bind/rndc.key

/bin/sh -c "designate-manage pool update" designate:
  cmd.run:
    - onchanges:
      - file: /etc/designate/pools.yaml

/bin/sh -c "designate-manage tlds import --input_file /etc/designate/tlds.conf" designate:
  cmd.run:
    - onchanges:
      - file: /etc/designate/tlds.conf
