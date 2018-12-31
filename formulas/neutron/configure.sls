include:
  - /formulas/neutron/install
  - formulas/common/base
  - formulas/common/networking

make_neutron_service:
  cmd.script:
    - source: salt://formulas/neutron/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        neutron_internal_endpoint: {{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['path'] }}
        neutron_public_endpoint: {{ pillar ['openstack_services']['neutron']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['neutron']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['neutron']['configuration']['public_endpoint']['path'] }}
        neutron_admin_endpoint: {{ pillar ['openstack_services']['neutron']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['neutron']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['neutron']['configuration']['admin_endpoint']['path'] }}
        neutron_service_password: {{ pillar ['neutron']['neutron_service_password'] }}

/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/neutron/files/neutron.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://nova:{{ pillar['nova']['nova_mysql_password'] }}@{{ address[0] }}/nova'
{% endfor %}
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['neutron']['neutron_service_password'] }}
        my_ip: {{ grains['ipv4'][0] }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}
        designate_url: fixme

/etc/neutron/api-paste.ini:
  file.managed:
    - source: salt://formulas/neutron/files/api-paste.ini

/etc/neutron/plugins/ml2/ml2_conf.ini:
  file.managed:
    - source: salt://formulas/neutron/files/ml2_conf.ini

/etc/neutron/plugins/ml2/linuxbridge_agent.ini:
  file.managed:
    - source: salt://formulas/neutron/files/linuxbridge_agent.ini
    - template: jinja
    - defaults:
        local_ip: {% salt['network.ip_addrs']('cidr=pillar['subnets']['private']')[0] %}

/etc/neutron/l3_agent.ini:
  file.managed:
    - source: salt://apps/openstack/neutron/files/l3_agent.ini
    - source_hash: salt://apps/openstack/neutron/files/hash

/etc/neutron/dhcp_agent.ini:
  file.managed:
    - source: salt://apps/openstack/neutron/files/dhcp_agent.ini
    - source_hash: salt://apps/openstack/neutron/files/hash

/etc/neutron/metadata_agent.ini:
  file.managed:
    - source: salt://apps/openstack/neutron/files/metadata_agent.ini
    - source_hash: salt://apps/openstack/neutron/files/hash
    - template: jinja
    - defaults:
        nova_metadata_host: nova_metadata_host = {{ pillar['nova_configuration']['internal_endpoint']['url'] }}
        metadata_proxy_shared_secret: metadata_proxy_shared_secret = {{ pillar['metadata_secret'] }}
