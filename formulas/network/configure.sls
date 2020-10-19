include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/network/files/neutron.conf
    - template: jinja
    - defaults:
        core_plugin: neutron.plugins.ml2.plugin.Ml2Plugin
        service_plugins: router
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='neutron', database='neutron') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['neutron']['neutron_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}
        designate_url: {{ constructor.base_endpoint_url_constructor(project='designate', service='designate', endpoint='public') }}
        designate_password: {{ pillar['designate']['designate_service_password'] }}
{% if grains['os_family'] == 'Debian' %}
        lock_path: /var/lock/neutron
{% elif grains['os_family'] == 'RedHat' %}
        lock_path: /var/lib/neutron/tmp
{% endif %}

/etc/neutron/plugins/ml2/ml2_conf.ini:
  file.managed:
    - source: salt://formulas/network/files/ml2_conf.ini
    - template: jinja
    - defaults:
        type_drivers: flat,vlan,vxlan
        tenant_network_types: vxlan
        mechanism_drivers: linuxbridge,l2population
        extension_drivers: port_security,dns_domain_ports
        ovn_nb_connection: ""
        ovn_sb_connection: ""
        ovn_l3_scheduler: ""
        ovn_native_dhcp: ""
        ovn_l3_mode: ""
        ovn_metadata_enabled: ""
        enable_distributed_floating_ip:  ""
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
    - source: salt://formulas/network/files/neutron_sudoers

### workaround for https://bugs.launchpad.net/neutron/+bug/1887281
arp_protect_fix:
  file.managed:
{% if grains['os_family'] == 'RedHat' %}
    - name: /usr/lib/python{{ grains['pythonversion'][0] }}.{{ grains['pythonversion'][1] }}/site-packages/neutron/plugins/ml2/drivers/linuxbridge/agent/arp_protect.py
{% elif grains['os_family'] == 'Debian' %}
    - name: /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/neutron/plugins/ml2/drivers/linuxbridge/agent/arp_protect.py
{% endif %}
    - source: salt://formulas/network/files/arp_protect.py
###

{% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
## this used to be a default but was changed to a boolean here:
## https://github.com/redhat-openstack/openstack-selinux/commit/9cfdb0f0aa681d57ca52948f632ce679d9e1f465
os_neutron_dac_override:
  selinux.boolean:
    - value: on
    - persist: True
    - watch_in:
      - service: neutron_linuxbridge_agent_service

## ref: https://github.com/redhat-openstack/openstack-selinux/commit/9460342f3e5a7214bd05b9cfa73a1896478d8785
os_dnsmasq_dac_override:
  selinux.boolean:
    - value: on
    - persist: True
    - watch_in:
      - service: neutron_dhcp_agent_service
{% endif %}

/etc/neutron/plugins/ml2/linuxbridge_agent.ini:
  file.managed:
    - source: salt://formulas/network/files/linuxbridge_agent.ini
    - template: jinja
    - defaults:
        local_ip: {{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}
{% for network in pillar['hosts'][grains['type']]['networks'] if network == 'public' %}
        public_interface: {{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }}
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

neutron_dhcp_agent_service:
  service.running:
    - name: neutron-dhcp-agent
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/dhcp_agent.ini

neutron_metadata_agent_service:
  service.running:
    - name: neutron-metadata-agent
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/metadata_agent.ini

neutron_l3_agent_service:
  service.running:
    - name: neutron-l3-agent
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/l3_agent.ini
