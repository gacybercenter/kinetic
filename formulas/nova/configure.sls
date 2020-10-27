include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

nova-manage api_db sync:
  cmd.run:
    - runas: nova
    - require:
      - file: /etc/nova/nova.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

nova-manage cell_v2 map_cell0:
  cmd.run:
    - runas: nova
    - require:
      - file: /etc/nova/nova.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

nova-manage cell_v2 create_cell --name=cell1 --verbose:
  cmd.run:
    - runas: nova
    - require:
      - file: /etc/nova/nova.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

nova-manage db sync:
  cmd.run:
    - runas: nova
    - require:
      - file: /etc/nova/nova.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

update_cells:
  cmd.run:
    - name: nova-manage cell_v2 list_cells | grep cell1 | cut -d" " -f4 | while read uuid;do nova-manage cell_v2 update_cell --cell_uuid $uuid;done
    - onchanges:
      - file: /etc/nova/nova.conf
    - watch_in:
      - service: nova_api_service
      - service: nova_scheduler_service
      - service: nova_conductor_service
      - service: nova_spiceproxy_service

{{ spawn.spawnzero_complete() }}

## This is lightning fast but I'm not sure how I feel about writing directly to the database
## outside the context of the API.  Should probably change to the flavor_present state
## once the openstack-ng modules are done in salt
## Also, there is a problem if bootstrapping a non-existent database, namely the jinja
## mysql query will fail.  This needs to be more intelligent.  Temp workaround is to
## only create flavors at very beginning, and not pick up pillar changes later in lifecycle
{% for flavor, attribs in pillar['flavors'].items() %}
create_{{ flavor }}:
  mysql_query.run:
    - database: nova_api
    - connection_pass: {{ pillar['nova']['nova_mysql_password'] }}
    - connection_user: nova
    - connection_host: {{ pillar['haproxy']['dashboard_domain'] }}
    - query: "INSERT INTO nova_api.flavors(name,memory_mb,vcpus,swap,flavorid,rxtx_factor,root_gb,ephemeral_gb,disabled,is_public) VALUES ('{{ flavor }}',{{ attribs['ram'] }},{{ attribs['vcpus'] }},0,'{{ salt['random.get_str']('64')|uuid }}',1,{{ attribs['disk'] }},0,0,1);"
    - output: "/root/{{ flavor }}"
    - require:
      - service: nova_api_service
      - service: nova_scheduler_service
      - service: nova_conductor_service
      - service: nova_spiceproxy_service
    - retry:
        attempts: 3
        interval: 10
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure
{% endfor %}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/nova/nova.conf:
  file.managed:
    - source: salt://formulas/nova/files/nova.conf
    - template: jinja
    - defaults:
        sql_connection_string: {{ constructor.mysql_url_constructor(user='nova', database='nova') }}
        api_sql_connection_string: {{ constructor.mysql_url_constructor(user='nova', database='nova_api') }}
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['nova']['nova_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ constructor.endpoint_url_constructor(project='glance', service='glance', endpoint='internal') }}
        metadata_proxy_shared_secret: {{ pillar['neutron']['metadata_proxy_shared_secret'] }}
        neutron_password: {{ pillar['neutron']['neutron_service_password'] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        console_domain: {{ pillar['haproxy']['console_domain'] }}
        token_ttl: {{ pillar['nova']['token_ttl'] }}

spice-html5:
  git.latest:
    - name: https://gitlab.com/gacybercenter/spice-html5.git
    - target: /usr/share/spice-html5
    - force_clone: True

nova_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-api
{% endif %}
    - enable: true
    - retry:
        attempts: 3
        interval: 10
    - watch:
      - file: /etc/nova/nova.conf

nova_scheduler_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-scheduler
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-scheduler
{% endif %}
    - enable: true
    - retry:
        attempts: 3
        interval: 10
    - watch:
      - file: /etc/nova/nova.conf

nova_conductor_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-conductor
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-conductor
{% endif %}
    - enable: true
    - retry:
        attempts: 3
        interval: 10
    - watch:
      - file: /etc/nova/nova.conf

nova_spiceproxy_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nova-spiceproxy
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-nova-spicehtml5proxy
{% endif %}
    - enable: true
    - retry:
        attempts: 3
        interval: 10
    - watch:
      - file: /etc/nova/nova.conf
