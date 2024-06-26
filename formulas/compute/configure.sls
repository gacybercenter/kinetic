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
  - /formulas/common/fluentd/configure
  - /formulas/common/ceph/configure

{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

### Calculate public interface - this is referenced a few times
### Potential to make 'interface calculator' macro
{% if salt['pillar.get']('hosts:'+grains['type']+':networks:public:bridge', False) == True %}
  {% set public_interface = 'public_br' %}
{% elif salt['pillar.get']('hosts:'+grains['type']+':networks:public:interfaces') | length > 1 %}
  {% set public_interface = 'public_bond' %}
{% else %}
  {% set public_interface = pillar['hosts'][grains['type']]['networks']['public']['interfaces'][0] %}
{% endif %}

{% set nova_uuid = pillar['ceph']['nova-uuid'] %}
{% set volumes_uuid = pillar['ceph']['volumes-uuid'] %}

conf-files:
  file.managed:
    - template: jinja
    - defaults:
        nova_uuid: {{ nova_uuid }}
        volumes_uuid: {{ volumes_uuid }}
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ constructor.endpoint_url_constructor(project='glance', service='glance', endpoint='internal') }}
        neutron_password: {{ pillar['neutron']['neutron_service_password'] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        rbd_secret_uuid: {{ pillar['ceph']['nova-uuid'] }}
        console_domain: {{ pillar['haproxy']['console_domain'] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
        compute_hosts: {{ constructor.host_file_constructor(role='compute')|yaml_encode }}
        gpu_hosts: {{ constructor.host_file_constructor(role='gpu')|yaml_encode }}
        explicitly_egress_direct: True
    - names:
      - /etc/modprobe.d/kvm.conf:
        - source: salt://formulas/compute/files/kvm.conf
      - /etc/ceph/ceph-nova.xml:
        - source: salt://formulas/compute/files/ceph-nova.xml
      - /etc/ceph/ceph-volumes.xml:
        - source: salt://formulas/compute/files/ceph-volumes.xml
      - /etc/nova/nova.conf:
        - source: salt://formulas/compute/files/nova.conf
      - /etc/sudoers.d/neutron_sudoers:
        - source: salt://formulas/compute/files/neutron_sudoers
      - /etc/neutron/neutron.conf:
        - source: salt://formulas/compute/files/neutron.conf
      - /etc/hosts:
        - source: salt://formulas/compute/files/hosts
      # - /etc/frr/daemons:
      #   - source: salt://formulas/common/frr/files/daemons

ceph_keyrings:
  file.managed:
    - names:
      - /etc/ceph/ceph.client.compute.keyring:
        - contents_pillar: ceph:ceph-client-compute-keyring
      - /etc/ceph/client.compute.key:
        - contents_pillar: ceph:ceph-client-compute-key
      - /etc/ceph/client.volumes.key:
        - contents_pillar: ceph:ceph-client-volumes-key
    - mode: "0640"
    - user: root
    - group: nova

libvirt_secrets:
  file.managed:
    - makedirs: True
    - template: jinja
    - defaults:
        nova_uuid: {{ nova_uuid }}
        volumes_uuid: {{ volumes_uuid }}
    - names:
      - /etc/libvirt/secrets/{{ nova_uuid }}.base64:
        - contents_pillar: ceph:ceph-client-compute-key
      - /etc/libvirt/secrets/{{ volumes_uuid }}.base64:
        - contents_pillar: ceph:ceph-client-volumes-key
      - /etc/libvirt/secrets/{{ nova_uuid }}.xml:
        - source: salt://formulas/compute/files/ceph-nova.xml
      - /etc/libvirt/secrets/{{ volumes_uuid }}.xml:
        - source: salt://formulas/compute/files/ceph-volumes.xml
    - mode: "0600"
    - user: root
    - group: root

###
## Nova Live Migration Setup
/var/lib/nova/.ssh/config:
  file.managed:
    - makedirs: True
    - user: nova
    - group: nova
    - mode: '0400'
    - source: salt://formulas/compute/files/config

/var/lib/nova/.ssh/id_rsa:
  file.managed:
    - makedirs: True
    - contents_pillar: nova_private_key
    - user: nova
    - group: nova
    - mode: '0600'
    - replace: False

/etc/pam.d/sshd:
  file.managed:
    - makedirs: True
    - source: salt://formulas/compute/files/sshd

/etc/ssh/sshd.allow:
  file.managed:
    - makedirs: True
    - contents: |
        nova
        root

nova:
  group.present:
    - system: True
  user.present:
    - shell: /bin/bash
    - createhome: True
    - home: /var/lib/nova
    - system: True
    - groups:
      - nova
      - libvirt

{% for key in pillar['nova_live_migration_auth_key'] %}
{{ key }}:
  ssh_auth.present:
    - user: nova
    - enc: {{ pillar['nova_live_migration_auth_key'][ key ]['encoding'] }}
{% endfor %}

nova_compute_service:
  service.running:
    - name: nova-compute
    - enable: true
    - watch:
      - file: /etc/nova/nova.conf

{% set neutron_backend = pillar['neutron']['backend'] %}
{% if neutron_backend != "networking-ovn" %}
/etc/neutron/plugins/ml2/{{ neutron_backend }}_agent.ini:
  file.managed:
    - source: salt://formulas/compute/files/{{ neutron_backend }}_agent.ini
    - template: jinja
    - defaults:
        local_ip: {{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}
        public_interface: {{ public_interface }}
  {% if neutron_backend == "openvswitch" %}
        extensions: qos
        bridge_mappings: public_br
        explicitly_egress_direct: True

create_bridge:
  openvswitch_bridge.present:
    - name: public_br

create_port:
  openvswitch_port.present:
    - name: {{ public_interface }}
    - bridge: public_br
  {% endif %}

neutron_{{ neutron_backend }}_agent_service:
  service.running:
    - name: neutron-{{ neutron_backend }}-agent
    - enable: true
    - watch:
      - file: conf-files
      - file: /etc/neutron/plugins/ml2/{{ neutron_backend }}_agent.ini

{% elif neutron_backend == "networking-ovn" %}
neutron-ovn-metadata-agent.ini:
  file.managed:
    - source: salt://formulas/compute/files/neutron_ovn_metadata_agent.ini
    - name: /etc/neutron/neutron_ovn_metadata_agent.ini
    - template: jinja
    - defaults:
        nova_metadata_host: {{ pillar['endpoints']['public'] }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}
        ovn_sb_connection: {{ constructor.ovn_sb_connection_constructor() }}

openvswitch_service:
  service.running:
    - name: openvswitch-switch
    - enable: true
    - watch:
      - file: conf-files
      - file: neutron-ovn-metadata-agent.ini

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

ovs-vsctl set open . external_ids:ovn-openflow-probe-interval=180 :
  cmd.run:
    - require:
      - service: openvswitch_service
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - unless:
      - ovs-vsctl get open . external-ids:ovn-openflow-probe-interval | grep -q "180"

ovsdb_listen:
  cmd.run:
    - name: ovs-vsctl set-manager ptcp:6640:127.0.0.1
    - unless:
      - ovs-vsctl get-manager | grep -q "ptcp:6640:127.0.0.1"

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
    - name: ovn-host
    - enable: true
    - require:
      - service: openvswitch_service
      - cmd: set_encap
      - cmd: set_encap_ip

ovn_metadata_service:
  service.running:
    - name: neutron-ovn-metadata-agent
    - enable: True
    - watch:
      - file: neutron-ovn-metadata-agent.ini
    - require:
      - cmd: ovsdb_listen
{% endif %}

libvirtd_service:
  service.running:
    - name: libvirtd
    - enable: True
    - watch:
      - file: /etc/libvirt/secrets/{{ nova_uuid }}.xml
      - file: /etc/libvirt/secrets/{{ volumes_uuid }}.xml
      - file: /etc/libvirt/secrets/{{ nova_uuid }}.base64
      - file: /etc/libvirt/secrets/{{ volumes_uuid }}.base64
    - require:
      - file: libvirt_secrets
