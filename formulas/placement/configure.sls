include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

placement-manage db sync:
  cmd.run:
    - runas: placement
    - require:
      - file: /etc/placement/placement.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/placement/placement.conf:
  file.managed:
    - source: salt://formulas/placement/files/placement.conf
    - template: jinja
    - defaults:
        sql_connection_string: {{ constructor.mysql_url_constructor(user='placement', database='placement') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['placement']['placement_service_password'] }}

{% if grains['os_family'] == 'Debian' %}

apache2_service:
  service.running:
    - name: apache2
    - enable: true
    - watch:
      - file: /etc/placement/placement.conf

{% elif grains['os_family'] == 'RedHat' %}

/etc/httpd/conf.d/00-placement-api.conf:
  file.managed:
    - source: salt://formulas/placement/files/00-placement-api.conf

apache2_service:
  service.running:
    - name: httpd
    - enable: true
    - watch:
      - file: /etc/placement/placement.conf
      - file: /etc/httpd/conf.d/00-placement-api.conf

{% endif %}
