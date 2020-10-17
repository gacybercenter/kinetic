include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/common/ceph/configure

{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

/etc/modprobe.d/kvm.conf:
  file.managed:
    - source: salt://formulas/compute/files/kvm.conf

/etc/frr/daemons:
  file.managed:
    - source: salt://formulas/common/frr/files/daemons

/etc/ceph/ceph.client.compute.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-compute-keyring
    - mode: 640
    - user: root
    - group: nova

/etc/ceph/client.compute.key:
  file.managed:
    - contents_pillar: ceph:ceph-client-compute-key
    - mode: 640
    - user: root
    - group: nova

/etc/ceph/ceph-nova.xml:
  file.managed:
    - source: salt://formulas/compute/files/ceph-nova.xml
    - template: jinja
    - defaults:
        uuid: {{ pillar['ceph']['nova-uuid'] }}

define_ceph_compute_key:
  cmd.run:
    - name: virsh secret-define --file /etc/ceph/ceph-nova.xml
    - unless:
      - virsh secret-list | grep -q {{ pillar['ceph']['nova-uuid'] }}

load_ceph_compute_key:
  cmd.run:
    - name: virsh secret-set-value --secret {{ pillar['ceph']['nova-uuid'] }} --base64 $(cat /etc/ceph/client.compute.key)
    - unless:
      - virsh secret-get-value {{ pillar['ceph']['nova-uuid'] }}

/etc/ceph/client.volumes.key:
  file.managed:
    - contents_pillar: ceph:ceph-client-volumes-key
    - mode: 640
    - user: nova
    - group: nova

/etc/ceph/ceph-volumes.xml:
  file.managed:
    - source: salt://formulas/compute/files/ceph-volumes.xml
    - template: jinja
    - defaults:
        uuid: {{ pillar['ceph']['volumes-uuid'] }}

define_ceph_volumes_key:
  cmd.run:
    - name: virsh secret-define --file /etc/ceph/ceph-volumes.xml
    - unless:
      - virsh secret-list | grep -q {{ pillar['ceph']['volumes-uuid'] }}

load_ceph_volumes_key:
  cmd.run:
    - name: virsh secret-set-value --secret {{ pillar['ceph']['volumes-uuid'] }} --base64 $(cat /etc/ceph/client.volumes.key)
    - unless:
      - virsh secret-get-value {{ pillar['ceph']['volumes-uuid'] }}

/etc/nova/nova.conf:
  file.managed:
    - source: salt://formulas/compute/files/nova.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['nova']['nova_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ constructor.endpoint_url_constructor(project='glance', service='glance', endpoint='internal') }}
        neutron_password: {{ pillar['neutron']['neutron_service_password'] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        rbd_secret_uuid: {{ pillar['ceph']['nova-uuid'] }}
        console_domain: {{ pillar['haproxy']['console_domain'] }}

{% if grains['os_family'] == 'RedHat' %}
spice-html5:
  git.latest:
    - name: https://github.com/freedesktop/spice-html5.git
    - target: /usr/share/spice-html5
{% endif %}

/etc/sudoers.d/neutron_sudoers:
  file.managed:
    - source: salt://formulas/compute/files/neutron_sudoers

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

{% if grains['os_family'] == 'RedHat' %}
libvirtd_service:
  service.running:
    - name: libvirtd
    - enable: true
    - require_in:
      - cmd: define_ceph_compute_key
      - cmd: load_ceph_compute_key
      - cmd: define_ceph_volumes_key
      - cmd: load_ceph_volumes_key
{% endif %}

{% if pillar['neutron']['backend'] == "linuxbridge" %}
/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/compute/files/neutron.conf
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

### workaround for https://bugs.launchpad.net/neutron/+bug/1887281
arp_protect_fix:
  file.managed:
  {% if grains['os_family'] == 'RedHat' %}
    - name: /usr/lib/python{{ grains['pythonversion'][0] }}.{{ grains['pythonversion'][1] }}/site-packages/neutron/plugins/ml2/drivers/linuxbridge/agent/arp_protect.py
  {% elif grains['os_family'] == 'Debian' %}
    - name: /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/neutron/plugins/ml2/drivers/linuxbridge/agent/arp_protect.py
  {% endif %}
    - source: salt://formulas/compute/files/arp_protect.py
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
  {% for network in pillar['hosts'][grains['type']]['networks'] if network == 'public' %}
        public_interface: {{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }}
  {% endfor %}

{% elif pillar['neutron']['backend'] == "networking-ovn" %}

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

  {% if salt['pillar.get']('hosts:'+grains['type']+':networks:public:bridge', False) == True %}
    {% set public_interface = 'public_br' %}
  {% elif salt['pillar.get']('hosts:'+grains['type']+':networks:public:interfaces') | length > 1 %}
    {% set public_interface = 'public_bond' %}
  {% else %}
    {% set public_interface = pillar['hosts'][grains['type']]['networks']['public']['interfaces'][0] %}
  {% endif %}

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
