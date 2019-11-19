include:
  - formulas/network/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

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
        ovn_nb_connection: ovn_nb_connection = tcp:10.100.6.43:6641
        ovn_sb_connection: ovn_sb_connection = tcp:10.100.6.43:6642
        ovn_l3_scheduler: ovn_l3_scheduler = leastloaded
        ovn_native_dhcp: ovn_native_dhcp = True
        ovn_l3_mode: ovn_l3_mode = True
        ovn_metadata_enabled: ovn_metadata_enabled = True
{% endif %}
        vni_ranges: 1:65536

{% if grains['os_family'] == 'RedHat' %}
plugin_symlink:
  file.symlink:
    - name: /etc/neutron/plugin.ini
    - target: /etc/neutron/plugins/ml2/ml2_conf.ini
{% endif %}

fs.inotify.max_user_instances:
  sysctl.present:
    - value: 1024

/etc/sudoers.d/neutron_sudoers:
  file.managed:
    - source: salt://formulas/neutron/files/neutron_sudoers

{% if pillar['neutron']['backend'] == "linuxbridge" %}

/etc/neutron/plugins/ml2/linuxbridge_agent.ini:
  file.managed:
    - source: salt://formulas/network/files/linuxbridge_agent.ini
    - template: jinja
    - defaults:
        local_ip: {{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}
{% for interface in pillar['virtual'][grains['type']]['networks']['interfaces'] %}
  {% if pillar['virtual'][grains['type']]['networks']['interfaces'][interface]['network'] == 'public' %}
        public_interface: {{ interface }}
  {% endif %}
{% endfor %}

/etc/neutron/l3_agent.ini:
  file.managed:
    - source: salt://formulas/network/files/l3_agent.ini

/etc/neutron/dhcp_agent.ini:
  file.managed:
    - source: salt://formulas/network/files/dhcp_agent.ini

/etc/neutron/metadata_agent.ini:
  file.managed:
    - source: salt://formulas/network/files/metadata_agent.ini
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

/etc/neutron/networking_ovn_metadata_agent.ini:
  file.managed:
    - source: salt://formulas/neutron/files/networking_ovn_metadata_agent.ini
    - template: jinja
    - defaults:
        nova_metadata_host: {{ pillar['endpoints']['public'] }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}

openvswitch_service:
  service.running:
    - name: openvswitch
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/networking_ovn_metadata_agent.ini

ovn_northd_service:
  service.running:
    - name: ovn-northd
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/networking_ovn_metadata_agent.ini
    - require:
      - service: openvswitch_service

ovn-nbctl set-connection ptcp:6641:0.0.0.0 -- set connection . inactivity_probe=60000:
  cmd.run:
    - require:
      - service: ovn_northd_service

ovn-sbctl set-connection ptcp:6642:0.0.0.0 -- set connection . inactivity_probe=60000:
  cmd.run:
    - require:
      - service: ovn_northd_service
{% endif %}
