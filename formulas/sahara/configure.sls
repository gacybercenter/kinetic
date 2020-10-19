include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

sahara-db-manage --config-file /etc/sahara/sahara.conf upgrade head:
  cmd.run:
    - runas: sahara
    - require:
      - file: /etc/sahara/sahara.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/sahara/sahara.conf:
  file.managed:
    - source: salt://formulas/sahara/files/sahara.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='sahara', database='sahara') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['sahara']['sahara_service_password'] }}
        host: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

sahara_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-sahara-api
{% endif %}
    - enable: True
    - watch:
      - file: /etc/sahara/sahara.conf

sahara_engine_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: sahara-engine
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-sahara-engine
{% endif %}
    - enable: True
    - watch:
      - file: /etc/sahara/sahara.conf
