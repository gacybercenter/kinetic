include:
  - /formulas/compute/install
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/ceph/common/configure

/etc/modprobe.d/kvm.conf:
  file.managed:
    - source: salt://formulas/compute/files/kvm.conf

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
        memcached_servers: |
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}:11211
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        password: {{ pillar['nova']['nova_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
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
        memcached_servers: |
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
{% if grains['os_family'] == 'Debian' %}
        lock_path: /var/lock/neutron
{% elif grains['os_family'] == 'RedHat' %}
        lock_path: /var/lib/neutron/tmp
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
{% for network in pillar['hosts'][grains['type']]['networks'] %}
  {% if pillar['hosts'][grains['type']]['networks'][network]['network'] == 'public' %}
        public_interface: {{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }}
  {% endif %}
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
        ovn_sb_connection: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          tcp:{{ address }}:6642
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}

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
    - name: |-
        ovs-vsctl set open . external-ids:ovn-remote=
        {%- for host, addresses in salt['mine.get']('role:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
          {%- for address in addresses -%}
            {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
        tcp:{{ address }}:6642
            {%- endif -%}
          {%- endfor -%}
          {% if loop.index < loop.length %},{% endif %}
        {%- endfor %}
    - require:
      - service: openvswitch_service
    - unless:
      - ovs-vsctl get open . external-ids:ovn-remote | grep -q "
        {%- for host, addresses in salt['mine.get']('role:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
          {%- for address in addresses -%}
            {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
        tcp:{{ address }}:6642
            {%- endif -%}
          {%- endfor -%}
          {% if loop.index < loop.length %},{% endif %}
        {%- endfor %}"

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
    - unless:
      - ovs-vsctl get-manager | grep -q "ptcp:6640:127.0.0.1"

{% for network in pillar['hosts'][grains['type']]['networks'] %}
  {% if pillar['hosts'][grains['type']]['networks'][network]['network'] == 'public' %}
enable_bridge:
  cmd.run:
    - name: ovs-vsctl --may-exist add-port br-provider {{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }}
    - require:
      - service: openvswitch_service
      - cmd: set_encap
      - cmd: set_encap_ip
      - cmd: make_bridge
      - cmd: map_bridge
    - unless:
      - ovs-vsctl port-to-br {{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }} | grep -q "br-provider"
  {% endif %}
{% endfor %}

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
