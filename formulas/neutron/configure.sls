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
        designate_password: fixme

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
        local_ip: {{ salt['network.ip_addrs'](cidr=pillar['subnets']['private'])[0] }}

/etc/neutron/l3_agent.ini:
  file.managed:
    - source: salt://formulas/neutron/files/l3_agent.ini

/etc/neutron/dhcp_agent.ini:
  file.managed:
    - source: salt://formulas/neutron/files/dhcp_agent.ini

/etc/neutron/metadata_agent.ini:
  file.managed:
    - source: salt://formulas/neutron/files/metadata_agent.ini
    - template: jinja
    - defaults:
        nova_metadata_host: {{ pillar['endpoints']['internal'] }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}

/bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron:
  cmd.run

fs.inotify.max_user_instances:
  sysctl.present:
    - value: 1024

/etc/sudoers.d/neutron_sudoers:
  file.managed:
    - source: salt://formulas/neutron/files/neutron_sudoers

neutron_server_service:
  service.running:
    - name: neutron-server
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini
      - file: /etc/neutron/api-paste.ini

neutron_linuxbridge_agent_service:
  service.running:
    - name: neutron-linuxbridge-agent
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini
      - file: /etc/neutron/api-paste.ini

neutron_dhcp_agent_service:
  service.running:
    - name: neutron-dhcp-agent
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini
      - file: /etc/neutron/api-paste.ini

neutron_metadata_agent_service:
  service.running:
    - name: neutron-metadata-agent
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini
      - file: /etc/neutron/api-paste.ini

neutron_l3_agent_service:
  service.running:
    - name: neutron-l3-agent
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini
      - file: /etc/neutron/api-paste.ini

mk_public_network:
  cmd.script:
    - source: salt://formulas/neutron/files/mkpublic.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}

