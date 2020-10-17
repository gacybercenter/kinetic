include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

cinder-manage db sync:
  cmd.run:
    - runas: cinder
    - require:
      - file: /etc/cinder/cinder.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/cinder/cinder.conf:
  file.managed:
    - source: salt://formulas/cinder/files/cinder.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='cinder', database='cinder') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor('keystone', 'keystone', 'public') }}
        auth_url: {{ constructor.endpoint_url_constructor('keystone', 'keystone', 'internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['cinder']['cinder_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        api_servers: {{ constructor.endpoint_url_constructor('glance', 'glance', 'public') }}
        rbd_secret_uuid: {{ pillar['ceph']['volumes-uuid'] }}

cinder_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-cinder-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf

cinder_scheduler_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: cinder-scheduler
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-cinder-scheduler
{% endif %}
    - enable: true
    - watch:
      - file: /etc/cinder/cinder.conf
