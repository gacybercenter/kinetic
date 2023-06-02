## Copyright 2018 Augusta University
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
  - /formulas/common/fluentd/fluentd

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

/etc/openstack/clouds.yml:
  file.managed:
    - source: salt://formulas/common/openstack/files/clouds.yml
    - makedirs: True
    - template: jinja
    - defaults:
        password: {{ pillar['openstack']['admin_password'] }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}

neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head:
  cmd.run:
    - runas: neutron
    - require:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% set start = pillar['networking']['addresses']['float_start'] %}
{% set end = pillar['networking']['addresses']['float_end'] %}
{% set dns = pillar['networking']['addresses']['float_dns'] %}
{% set gateway = pillar['networking']['addresses']['float_gateway'] %}
{% set cidr = pillar['networking']['subnets']['public'] %}

public_network:
  cmd.run:
    - name: openstack network create --external --share --provider-physical-network provider --provider-network-type flat public
    - require:
      - service: neutron_server_service
      - file: /etc/openstack/clouds.yml
    - unless:
      - openstack network list | awk '{print $4}' | grep -q public

public_subnet:
  cmd.run:
    - name: openstack subnet create --network public --allocation-pool start={{ start }},end={{ end }} --dns-nameserver {{ dns }} --gateway {{ gateway }} --subnet-range {{ cidr }} public_subnet
    - require:
      - service: neutron_server_service
      - file: /etc/openstack/clouds.yml
      - cmd: public_network
    - unless:
      - openstack subnet list | awk '{print $4}' | grep -q public_subnet

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

conf-files:
  file.managed:
    - source: salt://formulas/neutron/files/neutron.conf
    - template: jinja
    - defaults:
{% if pillar['neutron']['backend'] == "networking-ovn" %}
        service_plugins: neutron.services.ovn_l3.plugin.OVNL3RouterPlugin
        type_drivers: local,flat,vlan,geneve
        tenant_network_types: geneve
        mechanism_drivers: ovn
        extension_drivers: port_security
        ovn_nb_connection: {{ constructor.ovn_nb_connection_constructor() }}
        ovn_sb_connection: {{ constructor.ovn_sb_connection_constructor() }}
        ovn_l3_scheduler: leastloaded
        ovn_native_dhcp: True
        ovn_l3_mode: True
        ovn_metadata_enabled: True
        enable_distributed_floating_ip: False
{% else %}
        service_plugins: router
        type_drivers: {{ pillar['neutron']['openvswitch']['type_drivers'] }}
        tenant_network_types: {{ pillar['neutron']['openvswitch']['tenant_network_types'] }}
        mechanism_drivers: {{ pillar['neutron']['openvswitch']['mechanism_drivers'] }}
        extension_drivers: {{ pillar['neutron']['openvswitch']['extension_drivers'] }}
        ovn_nb_connection: ""
        ovn_sb_connection: ""
        ovn_l3_scheduler: ""
        ovn_native_dhcp: ""
        ovn_metadata_enabled: ""
        enable_distributed_floating_ip:  ""
{% endif %}
        core_plugin: neutron.plugins.ml2.plugin.Ml2Plugin
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='neutron', database='neutron') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['neutron']['neutron_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}
        designate_url: {{ constructor.endpoint_url_constructor(project='designate', service='designate', endpoint='public', base=True) }}
        designate_password: {{ pillar['designate']['designate_service_password'] }}
        dns_domain: {{ pillar['designate']['tld'] }}
        rpc_workers: {{ grains['num_cpus'] * 2 }}
        vni_ranges: {{ pillar['neutron']['openvswitch']['vni_ranges'] }}
{% if salt['pillar.get']('neutron:l3ha', 'False') == True %}
        max_l3_agents_per_router: {{ pillar['neutron']['max_l3_agents_per_router'] }}
{% endif %}
        dhcp_agents_per_network: {{ pillar['neutron']['dhcp_agents_per_network'] }}
    - names:
      - /etc/neutron/neutron.conf:
        - source: salt://formulas/neutron/files/neutron.conf
      - /etc/neutron/plugins/ml2/ml2_conf.ini:
        - source: salt://formulas/neutron/files/ml2_conf.ini
      - /etc/sudoers.d/neutron_sudoers:
        - source: salt://formulas/neutron/files/neutron_sudoers

{% if grains['os_family'] == 'RedHat' %}
plugin_symlink:
  file.symlink:
    - name: /etc/neutron/plugin.ini
    - target: /etc/neutron/plugins/ml2/ml2_conf.ini
    - require_in:
      - service: neutron_server_service
{% endif %}

fs.inotify.max_user_instances:
  sysctl.present:
    - value: 1024

neutron_server_service:
  service.running:
    - name: neutron-server
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
    - require:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/ml2_conf.ini
      - file: /etc/sudoers.d/neutron_sudoers