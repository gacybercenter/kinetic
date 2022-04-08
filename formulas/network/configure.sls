## Copyright 2019 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if salt['pillar.get']('hosts:'+grains['type']+':networks:public:bridge', False) == True %}
  {% set public_interface = 'public_br' %}
{% elif salt['pillar.get']('hosts:'+grains['type']+':networks:public:interfaces') | length > 1 %}
  {% set public_interface = 'public_bond' %}
{% else %}
  {% set public_interface = pillar['hosts'][grains['type']]['networks']['public']['interfaces'][0] %}
{% endif %}

{% set neutron_backend = pillar['neutron']['backend'] %}
{% if neutron_backend == 'networking-ovn' %}
ovn_use:
  event.send:
    - name: networking-ovn
    - data:
        config_error: "You are spinnning network nodes, but set networking-ovn as the backend. If you really want ovn set; spin up ovsdb nodes instead."
{% else %}

  {% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

  {% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

  {% endif %}

conf-files:
  file.managed:
    - makedirs: true
    - template: jinja
    - defaults:
        core_plugin: neutron.plugins.ml2.plugin.Ml2Plugin
        service_plugins: router
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='neutron', database='neutron') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        neutron_password: {{ pillar['neutron']['neutron_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}
        designate_url: {{ constructor.endpoint_url_constructor(project='designate', service='designate', endpoint='public', base=True) }}
        designate_password: {{ pillar['designate']['designate_service_password'] }}
        type_drivers: {{ pillar['neutron']['openvswitch']['type_drivers'] }}
        tenant_network_types: {{ pillar['neutron']['openvswitch']['tenant_network_types'] }}
        mechanism_drivers: {{ pillar['neutron']['openvswitch']['mechanism_drivers'] }}
        extension_drivers: {{ pillar['neutron']['openvswitch']['extension_drivers'] }}
        vni_ranges: {{ pillar['neutron']['openvswitch']['vni_ranges'] }}
        extensions: {{ pillar['neutron']['openvswitch']['extensions'] }}
        local_ip: {{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}
        public_interface: {{ public_interface }}
        bridge_mappings: public_br
        interface_driver: {{ neutron_backend }}
        nova_metadata_host: {{ pillar['endpoints']['public'] }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}
{% if salt['pillar.get']('neutron:l3ha', 'False') == True %}
        max_l3_agents_per_router: {{ pillar['neutron']['max_l3_agents_per_router'] }}
{% endif %}
        dhcp_agents_per_network: {{ pillar['neutron']['dhcp_agents_per_network'] }}
    - names:
      - /etc/neutron/neutron.conf:
        - source: salt://formulas/network/files/neutron.conf
      - /etc/neutron/plugins/ml2/ml2_conf.ini:
        - source: salt://formulas/network/files/ml2_conf.ini
      - /etc/sudoers.d/neutron_sudoers:
        - source: salt://formulas/network/files/neutron_sudoers
      - /etc/neutron/plugins/ml2/{{ neutron_backend }}_agent.ini:
        - source: salt://formulas/network/files/{{ neutron_backend }}_agent.ini
      - /etc/neutron/l3_agent.ini:
        - source: salt://formulas/network/files/l3_agent.ini
      - /etc/neutron/dhcp_agent.ini:
        - source: salt://formulas/network/files/dhcp_agent.ini
      - /etc/neutron/fwaas_driver.ini:
        - source: salt://formulas/network/files/fwaas_driver.ini
      - /etc/neutron/metadata_agent.ini:
        - source: salt://formulas/network/files/metadata_agent.ini

fs.inotify.max_user_instances:
  sysctl.present:
    - value: 1024

  {% if grains['os_family'] == 'RedHat' %}
plugin_symlink:
  file.symlink:
    - name: /etc/neutron/plugin.ini
    - target: /etc/neutron/plugins/ml2/ml2_conf.ini

    {% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
## this used to be a default but was changed to a boolean here:
## https://github.com/redhat-openstack/openstack-selinux/commit/9cfdb0f0aa681d57ca52948f632ce679d9e1f465
os_neutron_dac_override:
  selinux.boolean:
    - value: on
    - persist: True
    - watch_in:
      - service: neutron_{{ neutron_backend }}_agent_service

## ref: https://github.com/redhat-openstack/openstack-selinux/commit/9460342f3e5a7214bd05b9cfa73a1896478d8785
os_dnsmasq_dac_override:
  selinux.boolean:
    - value: on
    - persist: True
    - watch_in:
      - service: neutron_dhcp_agent_service
    {% endif %}
  {% endif %}

  {% if neutron_backend == "openvswitch" %}
create_bridge:
  openvswitch_bridge.present:
    - name: public_br
    - require:
      - service: neutron_openvswitch_agent_service

create_port:
  openvswitch_port.present:
    - name: {{ public_interface }}
    - bridge: public_br
    - require:
      - openvswitch_bridge: create_bridge
      - service: neutron_openvswitch_agent_service
  {% endif %}

neutron_{{ neutron_backend }}_agent_service:
  service.running:
    - name: neutron-{{ neutron_backend }}-agent
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/neutron/plugins/ml2/{{ neutron_backend }}_agent.ini

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
      - file: /etc/neutron/fwaas_driver.ini
{% endif %}