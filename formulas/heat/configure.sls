include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

heat-manage db_sync:
  cmd.run:
    - runas: heat
    - require:
      - file: /etc/heat/heat.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/heat/heat.conf:
  file.managed:
    - source: salt://formulas/heat/files/heat.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='heat', database='heat') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['heat']['heat_service_password'] }}
        clients_keystone_auth_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        ec2_authtoken_auth_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        heat_metadata_server_url: {{ constructor.endpoint_url_constructor(project='heat', service='heat-cfn', endpoint='internal', base=True) }}
        heat_waitcondition_server_url: {{ constructor.endpoint_url_constructor(project='heat', service='heat-cfn', endpoint='internal') }}/waitcondition

heat_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: heat-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-heat-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/heat/heat.conf

heat_api_cfn_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: heat-api-cfn
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-heat-api-cfn
{% endif %}
    - enable: true
    - watch:
      - file: /etc/heat/heat.conf

heat_engine_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: heat-engine
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-heat-engine
{% endif %}
    - enable: true
    - watch:
      - file: /etc/heat/heat.conf
