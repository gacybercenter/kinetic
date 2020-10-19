include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

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


mk_public_network:
  cmd.script:
    - source: salt://formulas/neutron/files/mkpublic.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        start: {{ pillar['networking']['addresses']['float_start'] }}
        end: {{ pillar['networking']['addresses']['float_end'] }}
        dns: {{ pillar['networking']['addresses']['float_dns'] }}
        gateway: {{ pillar['networking']['addresses']['float_gateway'] }}
        cidr: {{ pillar['networking']['subnets']['public'] }}
    - require:
      - service: neutron_server_service
    - retry:
        attempts: 3
        interval: 10
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/neutron/neutron.conf:
  file.managed:
    - source: salt://formulas/neutron/files/neutron.conf
    - template: jinja
    - defaults:
        core_plugin: neutron.plugins.ml2.plugin.Ml2Plugin
{% if pillar['neutron']['backend'] == "linuxbridge" %}
        service_plugins: router
{% elif pillar['neutron']['backend'] == "networking-ovn" %}
        service_plugins: neutron.services.ovn_l3.plugin.OVNL3RouterPlugin
{% endif %}
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='neutron', database='neutron') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['neutron']['neutron_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}
        designate_url: {{ constructor.base_endpoint_url_constructor(project='designate', service='designate', endpoint='public') }}
        designate_password: {{ pillar['designate']['designate_service_password'] }}
{% if grains['os_family'] == 'Debian' %}
        lock_path: /var/lock/neutron
{% elif grains['os_family'] == 'RedHat' %}
        lock_path: /var/lib/neutron/tmp
{% endif %}

/etc/neutron/plugins/ml2/ml2_conf.ini:
  file.managed:
    - source: salt://formulas/neutron/files/ml2_conf.ini
    - template: jinja
    - defaults:
{% if pillar['neutron']['backend'] == "linuxbridge" %}
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
{% elif pillar['neutron']['backend'] == "networking-ovn" %}
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
        enable_distributed_floating_ip: True
{% endif %}
        vni_ranges: 1:65536

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

/etc/sudoers.d/neutron_sudoers:
  file.managed:
    - source: salt://formulas/neutron/files/neutron_sudoers

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
