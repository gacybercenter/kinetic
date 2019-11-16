include:
  - formulas/designate/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

/bin/sh -c "designate-manage database sync" designate:
  cmd.run:
    - onlyif:
      - /bin/sh -c "designate-manage database version" designate | grep -q 102
    - require:
      - file: /etc/designate/designate.conf

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

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
        listen_api: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}:9001
        designate_public_endpoint: {{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['path'] }}

/etc/designate/tlds.conf:
  file.managed:
    - source: salt://formulas/designate/files/tlds.conf

/etc/bind/named.conf.options:
  file.managed:
    - source: salt://formulas/designate/files/named.conf.options
    - template: jinja
    - defaults:
        public_dns: {{ pillar['networking']['addresses']['float_dns'] }}

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


designate_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: designate-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-designate-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_central_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: designate-central
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-designate-central
{% endif %}
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_worker_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: designate-worker
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-designate-worker
{% endif %}
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_producer_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: designate-producer
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-designate-producer
{% endif %}
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_mdns_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: designate-mdns
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-designate-mdns
{% endif %}
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_bind9_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: bind9
{% elif grains['os_family'] == 'RedHat' %}
    - name: bind
{% endif %}
    - enable: true
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
