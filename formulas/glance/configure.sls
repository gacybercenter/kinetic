include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/common/ceph/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

glance-manage db_sync:
  cmd.run:
    - runas: glance
    - require:
      - file: /etc/glance/glance-api.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/ceph/ceph.client.images.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-images-keyring
    - mode: 640
    - user: root
    - group: glance

/etc/sudoers.d/ceph:
  file.managed:
    - contents:
      - ceph ALL = (root) NOPASSWD:ALL
      - Defaults:ceph !requiretty
    - mode: 644

/etc/glance/glance-api.conf:
  file.managed:
    - source: salt://formulas/glance/files/glance-api.conf
    - template: jinja
    - defaults:
        sql_connection_string: {{ constructor.mysql_url_constructor(user='glance', database='glance') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['glance']['glance_service_password'] }}

glance_api_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: glance-api
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-glance-api
{% endif %}
    - enable: true
    - watch:
      - file: /etc/glance/glance-api.conf
