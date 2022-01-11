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
    - names:
      - /etc/modprobe.d/kvm.conf:
        - source: salt://formulas/compute/files/kvm.conf
      - /etc/frr/daemons:
        - source: salt://formulas/common/frr/files/daemons
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

### temporary patches for multiarch
multiarch_patch:
  file.managed:
    - names:
{% if grains['os_family'] == 'RedHat' %}
      - /usr/lib/python{{ grains['pythonversion'][0] }}.{{ grains['pythonversion'][1] }}/site-packages/nova/virt/libvirt/driver.py:
        - source: salt://formulas/compute/files/driver.py
      - /usr/lib/python{{ grains['pythonversion'][0] }}.{{ grains['pythonversion'][1] }}/site-packages/nova/virt/libvirt/config.py:
        - source: salt://formulas/compute/files/config.py
      - /usr/lib/python{{ grains['pythonversion'][0] }}.{{ grains['pythonversion'][1] }}/site-packages/nova/objects/image_meta.py:
        - source: salt://formulas/compute/files/image_meta.py
{% elif grains['os_family'] == 'Debian' %}
      - /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/nova/virt/libvirt/driver.py:
        - source: salt://formulas/compute/files/driver.py
      - /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/nova/virt/libvirt/config.py:
        - source: salt://formulas/compute/files/config.py
      - /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/nova/objects/image_meta.py:
        - source: salt://formulas/compute/files/image_meta.py
{% endif %}
### /multiarch patches

{% if grains['os_family'] == 'RedHat' %}
spice-html5:
  git.latest:
    - name: https://github.com/freedesktop/spice-html5.git
    - target: /usr/share/spice-html5
{% endif %}

nova_compute_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-compute
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-compute
{% endif %}
    - enable: true
    - watch:
      - file: /etc/nova/nova.conf
      - file: multiarch_patch

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

create_bridge:
  openvswitch_bridge.present:
    - name: public_br

create_port:
  openvswitch_port.present:
    - name: {{ public_interface }}
    - bridge: public_br
  {% endif %}
  {% if grains['os_family'] == 'RedHat' %}
    {% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
## this used to be a default but was changed to a boolean here:
## https://github.com/redhat-openstack/openstack-selinux/commit/9cfdb0f0aa681d57ca52948f632ce679d9e1f465
os_neutron_dac_override:
  selinux.boolean:
    - value: on
    - persist: True
    - watch_in:
      - service: neutron_{{ neutron_backend }}_agent_service
    {% endif %}
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
  {% if grains['os_family'] == 'Debian' %}
    - name: openvswitch-switch
  {% elif grains['os_family'] == 'RedHat' %}
    - name: openvswitch
  {% endif %}
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
  {% if grains['os_family'] == 'Debian' %}
    - name: ovn-host
  {% elif grains['os_family'] == 'RedHat' %}
    - name: ovn-controller
  {% endif %}
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
