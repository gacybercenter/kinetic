include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

### Gateway configuration
{% if salt['pillar.get']('danos:enabled', False) == True %}
set haproxy group:
  danos.set_resourcegroup:
    - name: haproxy-group
    - type: address-group
    - description: list of current haproxy servers
    - values:
      - {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - username: {{ pillar['danos']['username'] }}
    - password: {{ pillar['danos_password'] }}
  {% if salt['pillar.get']('danos:endpoint', "gateway") == "gateway" %}
    - host: {{ grains['ip4_gw'] }}
  {% else %}
    - host: {{ pillar['danos']['endpoint'] }}
  {% endif %}

  {% if salt['mine.get']('G@role:share and G@build_phase:configure', 'network.ip_addrs', tgt_type='compound')|length != 0 %}
set nfs group:
  danos.set_resourcegroup:
    - name: manila-share-servers
    - type: address-group
    - description: list of current nfs-ganesha servers
    - values:
    {% for host, addresses in salt['mine.get']('G@role:share and G@build_phase:configure', 'network.ip_addrs', tgt_type='compound') | dictsort() %}
      {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
      - {{ address }}
      {%- endfor -%}
    {% endfor %}
    - username: {{ pillar['danos']['username'] }}
    - password: {{ pillar['danos_password'] }}
    {% if salt['pillar.get']('danos:endpoint', "gateway") == "gateway" %}
    - host: {{ grains['ip4_gw'] }}
    {% else %}
    - host: {{ pillar['danos']['endpoint'] }}
    {% endif %}
  {% endif %}

set haproxy static-mapping:
  danos.set_statichostmapping:
    - name: {{ pillar['haproxy']['dashboard_domain'] }}
    - address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - aliases:
      - {{ pillar['haproxy']['console_domain'] }}
      - {{ pillar['haproxy']['docs_domain'] }}
    - username: {{ pillar['danos']['username'] }}
    - password: {{ pillar['danos_password'] }}
  {% if salt['pillar.get']('danos:endpoint', "gateway") == "gateway" %}
    - host: {{ grains['ip4_gw'] }}
  {% else %}
    - host: {{ pillar['danos']['endpoint'] }}
  {% endif %}
{% endif %}

{% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
haproxy_connect_any:
  selinux.boolean:
    - value: True
    - persist: True
    - require:
      - sls: /formulas/haproxy/install
{% endif %}

acme_certs:
  acme.cert:
    - name: {{ pillar['haproxy']['dashboard_domain'] }}
    - aliases:
      - {{ pillar['haproxy']['console_domain'] }}
      - {{ pillar['haproxy']['docs_domain'] }}
      - {{ pillar['haproxy']['guacamole_domain'] }}
      - {{ pillar['haproxy']['webssh2_domain'] }}
    - email: {{ pillar['haproxy']['acme_email'] }}
    - renew: 14
{% if salt['pillar.get']('development:test_certs', False) == True %}
    - test_cert: True
{% endif %}
{% if salt['pillar.get']('danos:enabled', False) == True %}
    - require:
      - danos: set haproxy group
      - danos: set haproxy static-mapping
{% endif %}

create_master_pem:
  cmd.run:
    - name: cat /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/fullchain.pem /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/privkey.pem > /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/master.pem
    - creates: /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/master.pem
    - require:
      - acme: acme_certs

/etc/haproxy/haproxy.cfg:
  file.managed:
    - source: salt://formulas/haproxy/files/haproxy.cfg
    - template: jinja
{% if salt['pillar.get']('syslog_url', False) == False %}
  {% for host, addresses in salt['mine.get']('role:graylog', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
    {% for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
    - context:
        syslog: {{ address }}:5514
    {% endfor %}
  {% endfor %}
{% endif %}
    - defaults:
{% if salt['pillar.get']('syslog_url', False) != False %}
        syslog: {{ pillar['syslog_url'] }}
{% else %}
        syslog: 127.0.0.1:5514
{% endif %}
        seamless_reload: stats socket /var/run/haproxy.sock mode 600 expose-fd listeners level user
        hostname: {{ grains['id'] }}
        management_ip_address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
        console_domain:  {{ pillar['haproxy']['console_domain'] }}
        docs_domain:  {{ pillar['haproxy']['docs_domain'] }}
        guacamole_domain:  {{ pillar['haproxy']['guacamole_domain'] }}
        webssh2_domain:  {{ pillar['haproxy']['webssh2_domain'] }}
        # keystone_hosts: {{ constructor.haproxy_listener_constructor(role='keystone', port=pillar['openstack_services']['keystone']['configuration']['services']['keystone']['endpoints']['public']['port']) }}
        # glance_api_hosts: {{ constructor.haproxy_listener_constructor(role='glance', port=pillar['openstack_services']['glance']['configuration']['services']['glance']['endpoints']['public']['port']) }}
        # nova_compute_api_hosts: {{ constructor.haproxy_listener_constructor(role='nova', port=pillar['openstack_services']['nova']['configuration']['services']['nova']['endpoints']['public']['port']) }}
        # nova_metadata_api_hosts: {{ constructor.haproxy_listener_constructor(role='nova', port='8775') }}
        # placement_api_hosts: {{ constructor.haproxy_listener_constructor(role='placement', port=pillar['openstack_services']['placement']['configuration']['services']['placement']['endpoints']['public']['port']) }}
        # nova_spiceproxy_hosts: {{ constructor.haproxy_listener_constructor(role='nova', port='6082') }}
        # dashboard_hosts: {{ constructor.haproxy_listener_constructor(role='horizon', port='80') }}
        # docs_hosts: {{ constructor.haproxy_listener_constructor(role='antora', port='80') }}
        # neutron_api_hosts: {{ constructor.haproxy_listener_constructor(role='neutron', port=pillar['openstack_services']['neutron']['configuration']['services']['neutron']['endpoints']['public']['port']) }}
        # heat_api_hosts: {{ constructor.haproxy_listener_constructor(role='heat', port=pillar['openstack_services']['heat']['configuration']['services']['heat']['endpoints']['public']['port']) }}
        # heat_api_cfn_hosts: {{ constructor.haproxy_listener_constructor(role='heat', port=pillar['openstack_services']['heat']['configuration']['services']['heat-cfn']['endpoints']['public']['port']) }}
        # cinder_api_hosts: {{ constructor.haproxy_listener_constructor(role='cinder', port=pillar['openstack_services']['cinder']['configuration']['services']['cinderv3']['endpoints']['public']['port']) }}
        # designate_api_hosts: {{ constructor.haproxy_listener_constructor(role='designate', port=pillar['openstack_services']['designate']['configuration']['services']['designate']['endpoints']['public']['port']) }}
        # swift_hosts: {{ constructor.haproxy_listener_constructor(role='swift', port=pillar['openstack_services']['swift']['configuration']['services']['swift']['endpoints']['public']['port']) }}
        # zun_api_hosts: {{ constructor.haproxy_listener_constructor(role='zun', port=pillar['openstack_services']['zun']['configuration']['services']['zun']['endpoints']['public']['port']) }}
        # zun_wsproxy_hosts: {{ constructor.haproxy_listener_constructor(role='zun', port='6784') }}
        # barbican_hosts: {{ constructor.haproxy_listener_constructor(role='barbican', port=pillar['openstack_services']['barbican']['configuration']['services']['barbican']['endpoints']['public']['port']) }}
        # magnum_hosts: {{ constructor.haproxy_listener_constructor(role='magnum', port=pillar['openstack_services']['magnum']['configuration']['services']['magnum']['endpoints']['public']['port']) }}
        # sahara_hosts: {{ constructor.haproxy_listener_constructor(role='sahara', port=pillar['openstack_services']['sahara']['configuration']['services']['sahara']['endpoints']['public']['port']) }}
        # manila_hosts: {{ constructor.haproxy_listener_constructor(role='manila', port=pillar['openstack_services']['manila']['configuration']['services']['manilav2']['endpoints']['public']['port']) }}
        # mysql_hosts: |-
        #   {%- for host, addresses in salt['mine.get']('G@type:mysql and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() %}
        #     {%- for address in addresses -%}
        #       {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        #   server {{ host }} {{ address }}:3306 check inter 2000 rise 2 fall 5
        #       {%- endif -%}
        #     {%- endfor -%}
        #   {%- endfor %}
        #   {%- for host, addresses in salt['mine.get']('G@type:mysql and not G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() %}
        #     {%- for address in addresses -%}
        #       {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        #   server {{ host }} {{ address }}:3306 check inter 2000 rise 2 fall 5 backup
        #       {%- endif -%}
        #     {%- endfor -%}
        #   {%- endfor %}
        # guacamole_hosts: {{ constructor.haproxy_listener_constructor(role='guacamole', port='8080') }}
        # webssh2_hosts: {{ constructor.haproxy_listener_constructor(role='webssh2', port='2222') }}

haproxy_service_watch:
  service.running:
    - name: haproxy
    - reload: true
    - watch:
      - file: /etc/haproxy/haproxy.cfg
