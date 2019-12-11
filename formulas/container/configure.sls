include:
  - formulas/container/install
  - formulas/common/base
  - formulas/common/networking

/etc/zun/zun.conf:
  file.managed:
    - source: salt://formulas/container/files/zun.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://zun:{{ pillar['zun']['zun_mysql_password'] }}@{{ address[0] }}/zun'
{% endfor %}
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        auth_strategy: auth_strategy = keystone
        auth_type: auth_type = password
        auth_version: auth_version = v3
        auth_protocol: auth_protocol = http
        password: {{ pillar['zun']['zun_service_password'] }}
        my_ip: my_ip = {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
        docker_ip: docker_remote_api_host = {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

/etc/kuryr/kuryr.conf:
  file.managed:
    - source: salt://formulas/container/files/kuryr.conf
    - template: jinja
    - defaults:
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        password: {{ pillar ['zun']['kuryr_service_password'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}

{% if pillar['neutron']['backend'] == "linuxbridge" %}

/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/container/files/neutron.conf
    - makedirs: true
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
{% if grains['os_family'] == 'RedHat' %}
    - name: openvswitch
{% elif grains['os_family'] == 'Debian' %}
    - name: openvswitch-switch
{% endif %}
    - enable: true

{% for server, address in salt['mine.get']('type:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
ovs-vsctl set open . external-ids:ovn-remote=tcp:{{ address[0] }}:6642:
  cmd.run:
    - require:
      - service: openvswitch_service
    - unless:
      - ovs-vsctl get open . external-ids:ovn-remote | grep -q "tcp:{{ address[0] }}:6642"
{% endfor %}

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

{% for interface in pillar['hosts'][grains['type']]['networks']['interfaces'] %}
  {% if pillar['hosts'][grains['type']]['networks']['interfaces'][interface]['network'] == 'public' %}
enable_bridge:
  cmd.run:
    - name: ovs-vsctl --may-exist add-port br-provider {{ interface }}
    - require:
      - service: openvswitch_service
      - cmd: set_encap
      - cmd: set_encap_ip
      - cmd: make_bridge
      - cmd: map_bridge
    - unless:
      - ovs-vsctl port-to-br {{ interface }} | grep -q "br-provider"
  {% endif %}
{% endfor %}

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
        etcd_cluster: |
          etcd://
          {%- for host, addresses in salt['mine.get']('role:etcd', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
                {{ address }}:2379
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
    - requires:
      - /formulas/container/install

/etc/systemd/system/zun-compute.service:
  file.managed:
    - source: salt://formulas/container/files/zun-compute.service
    - requires:
      - /formulas/container/install

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

zun_compute_service:
  service.running:
    - enable: true
    - name: zun-compute
    - watch:
      - file: /etc/zun/zun.conf
