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

{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if salt['pillar.get']('hosts:'+grains['type']+':networks:public:bridge', False) == True %}
  {% set public_interface = 'public_br' %}
{% elif salt['pillar.get']('hosts:'+grains['type']+':networks:public:interfaces') | length > 1 %}
  {% set public_interface = 'public_bond' %}
{% else %}
  {% set public_interface = pillar['hosts'][grains['type']]['networks']['public']['interfaces'][0] %}
{% endif %}

/etc/zun/zun.conf:
  file.managed:
    - source: salt://formulas/container/files/zun.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='zun', database='zun') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['zun']['zun_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
        docker_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

/etc/kuryr/kuryr.conf:
  file.managed:
    - source: salt://formulas/container/files/kuryr.conf
    - template: jinja
    - defaults:
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        password: {{ pillar ['zun']['kuryr_service_password'] }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}

{% if pillar['neutron']['backend'] == "linuxbridge" %}

/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/container/files/neutron.conf
    - makedirs: true
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['neutron']['neutron_service_password'] }}
  {% if grains['os_family'] == 'Debian' %}
        lock_path: /var/lock/neutron
  {% elif grains['os_family'] == 'RedHat' %}
        lock_path: /var/lib/neutron/tmp
  {% endif %}

/etc/sudoers.d/neutron_sudoers:
  file.managed:
    - source: salt://formulas/compute/files/neutron_sudoers

### workaround for https://bugs.launchpad.net/neutron/+bug/1887281
arp_protect_fix:
  file.managed:
{% if grains['os_family'] == 'RedHat' %}
    - name: /usr/lib/python{{ grains['pythonversion'][0] }}.{{ grains['pythonversion'][1] }}/site-packages/neutron/plugins/ml2/drivers/linuxbridge/agent/arp_protect.py
{% elif grains['os_family'] == 'Debian' %}
    - name: /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/neutron/plugins/ml2/drivers/linuxbridge/agent/arp_protect.py
{% endif %}
    - source: salt://formulas/container/files/arp_protect.py
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
{% endif %}

neutron_linuxbridge_agent_service:
  service.running:
    - name: neutron-linuxbridge-agent
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
      - file: /etc/neutron/plugins/ml2/linuxbridge_agent.ini

/etc/neutron/plugins/ml2/linuxbridge_agent.ini:
  file.managed:
    - source: salt://formulas/compute/files/linuxbridge_agent.ini
    - template: jinja
    - defaults:
        local_ip: {{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}
        public_interface: {{ public_interface }}

{% elif pillar['neutron']['backend'] == "networking-ovn" %}

openvswitch_service:
  service.running:
{% if grains['os_family'] == 'RedHat' %}
    - name: openvswitch
{% elif grains['os_family'] == 'Debian' %}
    - name: openvswitch-switch
{% endif %}
    - enable: true

set-ovn-remote:
  cmd.run:
    - name: ovs-vsctl set open . external-ids:ovn-remote={{ constructor.ovn_sb_connection_constructor() }}
    - require:
      - service: openvswitch_service
    - unless:
      - ovs-vsctl get open . external-ids:ovn-remote | grep -q "{{ constructor.ovn_sb_connection_constructor() }}"

set_encap:
  cmd.run:
    - name: ovs-vsctl set open . external-ids:ovn-encap-type=geneve
    - require:
      - service: openvswitch_service
    - unless:
      - ovs-vsctl get open . external-ids:ovn-encap-type | grep -q "geneve"

set_encap_ip:
  cmd.run:
    - name: ovs-vsctl set open . external-ids:ovn-encap-ip={{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}
    - require:
      - service: openvswitch_service
      - cmd: set_encap
    - unless:
      - ovs-vsctl get open . external-ids:ovn-encap-ip | grep -q "{{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}"

make_bridge:
  cmd.run:
    - name: ovs-vsctl --may-exist add-br br-provider -- set bridge br-provider protocols=OpenFlow13
    - require:
      - service: openvswitch_service
      - cmd: set_encap
      - cmd: set_encap_ip
    - unless:
      - ovs-vsctl br-exists br-provider

map_bridge:
  cmd.run:
    - name: ovs-vsctl set open . external-ids:ovn-bridge-mappings=provider:br-provider
    - require:
      - service: openvswitch_service
      - cmd: set_encap
      - cmd: set_encap_ip
      - cmd: make_bridge
    - unless:
      - ovs-vsctl get open . external-ids:ovn-bridge-mappings | grep -q "provider:br-provider"

ovs-vsctl set open . external_ids:ovn-remote-probe-interval=180000 :
  cmd.run:
    - require:
      - service: openvswitch_service
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - unless:
      - ovs-vsctl get open . external-ids:ovn-remote-probe-interval | grep -q "180000"

ovs-vsctl set open . external_ids:ovn-openflow-probe-interval=60 :
  cmd.run:
    - require:
      - service: openvswitch_service
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - unless:
      - ovs-vsctl get open . external-ids:ovn-openflow-probe-interval | grep -q "60"

ovsdb_listen:
  cmd.run:
    - name: ovs-vsctl set-manager ptcp:6640:127.0.0.1
    - require:
      - cmd: map_bridge
    - unless:
      - ovs-vsctl get-manager | grep -q "ptcp:6640:127.0.0.1"

## kuryr-libnetwork does not work with ovn by default
## you need to add a localhost remote and adjust the ovs-vsctl commands
## to use the correct remote.  These should be capture in configuration
## options upstream

modify_ovs_script:
  file.managed:
    - name: /usr/local/libexec/kuryr/ovs
    - source: salt://formulas/container/files/ovs
    - require:
      - cmd: ovsdb_listen

enable_bridge:
  cmd.run:
    - name: ovs-vsctl --may-exist add-port br-provider {{ public_interface }}
    - require:
      - service: openvswitch_service
      - cmd: set_encap
      - cmd: set_encap_ip
      - cmd: make_bridge
      - cmd: map_bridge
    - unless:
      - ovs-vsctl port-to-br {{ public_interface }} | grep -q "br-provider"

ovn_controller_service:
  service.running:
  {% if grains['os_family'] == 'RedHat' %}
    - name: ovn-controller
  {% elif grains['os_family'] == 'Debian' %}
    - name: ovn-host
  {% endif %}
    - enable: true
    - require:
      - service: openvswitch_service
      - cmd: set_encap
      - cmd: set_encap_ip
{% endif %}

/etc/sudoers.d/zun_sudoers:
  file.managed:
    - source: salt://formulas/container/files/zun_sudoers
    - requires:
      - /formulas/container/install

/etc/zun/rootwrap.conf:
  file.managed:
    - source: salt://formulas/container/files/rootwrap.conf
    - requires:
      - /formulas/container/install

/etc/zun/rootwrap.d/zun.filters:
  file.managed:
    - source: salt://formulas/container/files/zun.filters
    - requires:
      - /formulas/container/install

/etc/systemd/system/docker.service.d/docker.conf:
  file.managed:
    - source: salt://formulas/container/files/docker.conf
    - makedirs: True
    - template: jinja
    - defaults:
        etcd_cluster: {{ constructor.etcd_connection_constructor() }}
    - requires:
      - /formulas/container/install

/etc/containerd/config.toml:
  file.managed:
    - source: salt://formulas/container/files/config.toml
    - template: jinja
    - defaults:
        zun_group_id: {{ salt['group.info']('zun')['gid'] }}

cni_plugins:
  archive.extracted:
    - name: /opt/cni/bin
    - source: https://github.com/containernetworking/plugins/releases/download/v0.8.4/cni-plugins-linux-amd64-v0.8.4.tgz
    - source_hash: https://github.com/containernetworking/plugins/releases/download/v0.8.4/cni-plugins-linux-amd64-v0.8.4.tgz.sha512

install_zun_cni:
  cmd.run:
    - name: install -o zun -m 0555 -D /usr/local/bin/zun-cni /opt/cni/bin/zun-cni
    - creates:
      - /opt/cni/bin/zun-cni

/etc/systemd/system/zun-compute.service:
  file.managed:
    - source: salt://formulas/container/files/zun-compute.service
    - requires:
      - /formulas/container/install

/etc/systemd/system/zun-cni-daemon.service:
  file.managed:
    - source: salt://formulas/container/files/zun-cni-daemon.service
    - requires:
      - archive: cni_plugins
      - cmd: install_zun_cni

/etc/systemd/system/kuryr-libnetwork.service:
  file.managed:
    - source: salt://formulas/container/files/kuryr-libnetwork.service
    - requires:
      - /formulas/container/install

systemctl daemon-reload:
  cmd.wait:
    - watch:
      - file: /etc/systemd/system/docker.service.d/docker.conf
      - file: /etc/systemd/system/zun-compute.service
      - file: /etc/systemd/system/kuryr-libnetwork.service
      - file: /etc/systemd/system/zun-cni-daemon.service

docker_service:
  service.running:
    - enable: true
    - name: docker
    - watch:
      - file: /etc/systemd/system/docker.service.d/docker.conf

kuryr_libnetwork_service:
  service.running:
    - enable: true
    - name: kuryr-libnetwork
    - watch:
      - file: /etc/kuryr/kuryr.conf

containerd_service:
  service.running:
    - enable: true
    - name: containerd
    - watch:
      - file: /etc/containerd/config.toml

zun_compute_service:
  service.running:
    - enable: true
    - name: zun-compute
    - watch:
      - file: /etc/zun/zun.conf

zun_cni_daemon_service:
  service.running:
    - enable: true
    - name: zun-cni-daemon
    - watch:
      - file: /etc/zun/zun.conf
