include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

barbican-manage db upgrade:
  cmd.run:
    - runas: barbican
    - require:
      - file: /etc/barbican/barbican.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/barbican/barbican.conf:
  file.managed:
    - source: salt://formulas/barbican/files/barbican.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: sql_+{{ constructor.mysql_url_constructor('barbican', 'barbican') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor('keystone', 'keystone', 'public') }}
        auth_url: {{ constructor.endpoint_url_constructor('keystone', 'keystone', 'internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['barbican']['barbican_service_password'] }}
        kek: kek = '{{ pillar['barbican']['simplecrypto_key'] }}'

{% if grains['os_family'] == 'RedHat' %}
/etc/httpd/conf.d/wsgi-barbican.conf:
  file.managed:
    - source: salt://formulas/barbican/files/wsgi-barbican.conf
{% endif %}

barbican_keystone_listener_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: barbican-keystone-listener
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-barbican-keystone-listener
{% endif %}
    - enable: True
    - watch:
      - file: /etc/barbican/barbican.conf

barbican_worker_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: barbican-worker
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-barbican-worker
{% endif %}
    - enable: True
    - watch:
      - file: /etc/barbican/barbican.conf

barbican_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: httpd
{% endif %}
    - enable: true
    - watch:
      - file: /etc/barbican/barbican.conf
{% if grains['os_family'] == 'RedHat' %}
      - file: /etc/httpd/conf.d/wsgi-barbican.conf
{% endif %}
