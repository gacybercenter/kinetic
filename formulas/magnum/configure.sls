include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

magnum-db-manage upgrade:
  cmd.run:
    - runas: magnum
    - require:
      - file: /etc/magnum/magnum.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}


/etc/magnum/magnum.conf:
  file.managed:
    - source: salt://formulas/magnum/files/magnum.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='magnum', database='magnum') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['magnum']['magnum_service_password'] }}
        host: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

magnum_conductor_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: magnum-conductor
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-magnum-conductor
{% endif %}
    - enable: True
    - watch:
      - file: /etc/magnum/magnum.conf

magnum_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: magnum-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-magnum-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/magnum/magnum.conf
