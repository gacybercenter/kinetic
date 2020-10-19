include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

manila-manage db sync:
  cmd.run:
    - runas: manila
    - require:
      - file: /etc/manila/manila.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

make_nfs_share_type:
  cmd.script:
    - source: salt://formulas/manila/files/mknfs.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
    - require:
      - service: manila_api_service
      - service: manila_scheduler_service
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

/var/lib/manila/tmp:
  file.directory:
    - makedirs: true
    - user: manila
    - group: manila

/etc/manila/manila.conf:
  file.managed:
    - source: salt://formulas/manila/files/manila.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='manila', database='manila') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['manila']['manila_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}

manila_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: manila-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-manila-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/manila/manila.conf

manila_scheduler_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: manila-scheduler
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-manila-scheduler
{% endif %}
    - enable: true
    - watch:
      - file: /etc/manila/manila.conf
