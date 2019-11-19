include:
  - formulas/compute/install
  - formulas/common/base
  - formulas/common/networking
  - formulas/ceph/common/configure

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
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['nova']['nova_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
        neutron_password: {{ pillar['neutron']['neutron_service_password'] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        rbd_secret_uuid: {{ pillar['ceph']['nova-uuid'] }}
        console_domain: {{ pillar['haproxy']['console_domain'] }}

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

/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/compute/files/neutron.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['neutron']['neutron_service_password'] }}
{% if grains['os_family'] == 'Debian' %}
        lock_path: /var/lock/neutron
{% elif grains['os_family'] == 'RedHat' %}
        lock_path: /var/lib/neutron/tmp
{% endif %}

/etc/sudoers.d/neutron_sudoers:
  file.managed:
    - source: salt://formulas/compute/files/neutron_sudoers

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
{% for interface in pillar['hosts'][grains['type']]['networks']['interfaces'] %}
  {% if pillar['hosts'][grains['type']]['networks']['interfaces'][interface]['network'] == 'public' %}
        public_interface: {{ interface }}
  {% endif %}
{% endfor %}

{% elif pillar['neutron']['backend'] == "networking-ovn" %}

openvswitch_service:
  service.running:
    - name: openvswitch
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf

ovs-vsctl set open . external-ids:ovn-remote=tcp:10.100.6.43:6642:
  cmd.run:
    - require:
      - service: openvswitch_service

set_encap:
  cmd.run:
    - name: ovs-vsctl set open . external-ids:ovn-encap-type=geneve,vxlan
    - require:
      - service: openvswitch_service

set_encap_ip:
  cmd.run:
    - name: ovs-vsctl set open . external-ids:ovn-encap-ip={{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['private'])[0] }}
    - require:
      - service: openvswitch_service

ovn_controller_service:
  service.running:
    - name: ovn-controller
    - enable: true
    - watch:
      - file: /etc/neutron/neutron.conf
    - require:
      - service: openvswitch_service
      - cmd: set_encap
      - cmd: set_encap_ip

{% endif %}
