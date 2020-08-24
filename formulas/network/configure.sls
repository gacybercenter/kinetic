include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

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

/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/network/files/neutron.conf
    - template: jinja
    - defaults:
        core_plugin: neutron.plugins.ml2.plugin.Ml2Plugin
        service_plugins: router
        sql_connection_string: 'connection = mysql+pymysql://neutron:{{ pillar['neutron']['neutron_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/neutron'
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
    - source: salt://formulas/neutron/files/neutron_sudoers

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
      - file: /etc/neutron/l3_agent.ini
      - file: /etc/neutron/dhcp_agent.ini
      - file: /etc/neutron/metadata_agent.ini

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
