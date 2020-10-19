include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

zun-db-manage upgrade:
  cmd.run:
    - runas: zun
    - require:
      - file: /etc/zun/zun.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/zun/zun.conf:
  file.managed:
    - source: salt://formulas/zun/files/zun.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='zun', database='zun') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        auth_strategy: auth_strategy = keystone
        auth_type: auth_type = password
        auth_version: auth_version = v3
        auth_protocol: auth_protocol = https
        password: {{ pillar['zun']['zun_service_password'] }}
        api: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        wsproxy_host: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}

/etc/sudoers.d/zun_sudoers:
  file.managed:
    - source: salt://formulas/zun/files/zun_sudoers
    - requires:
      - /formulas/zun/install

/etc/zun/api-paste.ini:
  file.managed:
    - source: salt://formulas/zun/files/api-paste.ini
    - requires:
      - sls: /formulas/zun/install

/etc/systemd/system/zun-api.service:
  file.managed:
    - source: salt://formulas/zun/files/zun-api.service
    - requires:
      - sls: /formulas/zun/install

/etc/systemd/system/zun-wsproxy.service:
  file.managed:
    - source: salt://formulas/zun/files/zun-wsproxy.service
    - requires:
      - sls: /formulas/zun/install

zun_api_service:
  service.running:
    - name: zun-api
    - enable: true
    - watch:
      - file: /etc/zun/zun.conf

zun_wsproxy_service:
  service.running:
    - name: zun-wsproxy
    - enable: true
    - watch:
      - file: /etc/zun/zun.conf
