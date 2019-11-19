include:
  - /formulas/neutron/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

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

neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head:
  cmd.run:
    - runas: neutron
    - require:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini
      - file: /etc/neutron/api-paste.ini
    - unless:
      - neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini current | grep -q 5c85685d616d

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/neutron/files/neutron.conf
    - template: jinja
    - defaults:
        core_plugin: neutron.plugins.ml2.plugin.Ml2Plugin
{% if pillar['neutron']['backend'] == "linuxbridge" %}
        service_plugins: router
{% elif pillar['neutron']['backend'] == "networking-ovn" %}
        service_plugins: networking_ovn.l3.l3_ovn.OVNL3RouterPlugin
{% endif %}
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://neutron:{{ pillar['neutron']['neutron_mysql_password'] }}@{{ address[0] }}/neutron'
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
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}
        designate_url: {{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['port'] }}
        designate_password: {{ pillar['designate']['designate_service_password'] }}
{% if grains['os_family'] == 'Debian' %}
        lock_path: /var/lock/neutron
{% elif grains['os_family'] == 'RedHat' %}
        lock_path: /var/lib/neutron/tmp
{% endif %}

/etc/neutron/api-paste.ini:
  file.managed:
    - source: salt://formulas/neutron/files/api-paste.ini

/etc/neutron/plugins/ml2/ml2_conf.ini:
  file.managed:
    - source: salt://formulas/neutron/files/ml2_conf.ini
    - template: jinja
    - defaults:
{% if pillar['neutron']['backend'] == "linuxbridge" %}
        type_drivers: flat,vlan,vxlan
        tenant_network_types: vxlan
        mechanism_drivers: linuxbridge,l2population
        extension_drivers: port_security,dns_domain_ports
        ovn_nb_connection: ""
        ovn_sb_connection: ""
        ovn_l3_scheduler: ""
{% elif pillar['neutron']['backend'] == "networking-ovn" %}
        type_drivers: local,flat,vlan,geneve
        tenant_network_types: geneve
        mechanism_drivers: ovn
        extension_drivers: port_security
        ovn_nb_connection: ovn_nb_connection = tcp:10.100.5.138:6641
        ovn_sb_connection: ovn_sb_connection = tcp:10.100.5.138:6642
        ovn_l3_scheduler: ovn_l3_scheduler = leastloaded
{% endif %}
        vni_ranges: 1:65536

{% if grains['os_family'] == 'RedHat' %}
plugin_symlink:
  file.symlink:
    - name: /etc/neutron/plugin.ini
    - target: /etc/neutron/plugins/ml2/ml2_conf.ini
{% endif %}

/etc/neutron/plugins/ml2/linuxbridge_agent.ini:
  file.managed:
    - source: salt://formulas/neutron/files/linuxbridge_agent.ini
    - template: jinja
    - defaults:
        local_ip: {{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}
{% for interface in pillar['virtual'][grains['type']]['networks']['interfaces'] %}
  {% if pillar['virtual'][grains['type']]['networks']['interfaces'][interface]['network'] == 'public' %}
        public_interface: {{ interface }}
  {% endif %}
{% endfor %}

fs.inotify.max_user_instances:
  sysctl.present:
    - value: 1024

/etc/sudoers.d/neutron_sudoers:
  file.managed:
    - source: salt://formulas/neutron/files/neutron_sudoers

neutron_server_service:
  service.running:
    - name: neutron-server
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/api-paste.ini
{% if pillar['neutron']['backend'] == "linuxbridge" %}
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini

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
        nova_metadata_host: {{ pillar['endpoints']['public'] }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}

neutron_linuxbridge_agent_service:
  service.running:
    - name: neutron-linuxbridge-agent
    - enable: true
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
    - enable: true
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
    - enable: true
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
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini
      - file: /etc/neutron/api-paste.ini

{% elif pillar['neutron']['backend'] == "networking-ovn" %}
openvswitch_service:
  service.running:
    - name: openvswitch
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini

ovn_northd_service:
  service.running:
    - name: ovn-northd
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini

ovn-nbctl set-connection ptcp:6641:0.0.0.0 -- set connection . inactivity_probe=60000:
  cmd.run:
    - require:
      - service: ovn_northd_service

ovn-sbctl set-connection ptcp:6642:0.0.0.0 -- set connection . inactivity_probe=60000:
  cmd.run:
    - require:
      - service: ovn_northd_service
{% endif %}

{% if grains['spawning'] == 0 %}

mk_public_network:
  cmd.script:
    - source: salt://formulas/neutron/files/mkpublic.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        start: {{ pillar['networking']['addresses']['float_start'] }}
        end: {{ pillar['networking']['addresses']['float_end'] }}
        dns: {{ pillar['networking']['addresses']['float_dns'] }}
        gateway: {{ pillar['networking']['addresses']['float_gateway'] }}
        cidr: {{ pillar['networking']['subnets']['public'] }}

{% endif %}
