include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

make_magnum_service:
  cmd.script:
    - source: salt://formulas/magnum/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        magnum_internal_endpoint: {{ pillar ['openstack_services']['magnum']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['magnum']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['magnum']['configuration']['internal_endpoint']['path'] }}
        magnum_public_endpoint: {{ pillar ['openstack_services']['magnum']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['magnum']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['magnum']['configuration']['public_endpoint']['path'] }}
        magnum_admin_endpoint: {{ pillar ['openstack_services']['magnum']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['magnum']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['magnum']['configuration']['admin_endpoint']['path'] }}
        magnum_service_password: {{ pillar ['magnum']['magnum_service_password'] }}

magnum-db-manage upgrade:
  cmd.run:
    - runas: magnum
    - require:
      - file: /etc/magnum/magnum.conf

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

  {% from 'formulas/common/macros/spawn.sls' import check_spawnzero_status with context %}
    {{ check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/magnum/magnum.conf:
  file.managed:
    - source: salt://formulas/magnum/files/magnum.conf
    - template: jinja
    - defaults:
        transport_url: |-
          rabbit://
          {%- for host, addresses in salt['mine.get']('role:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address }}
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        connection: mysql+pymysql://magnum:{{ pillar['magnum']['magnum_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/magnum
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}
        memcached_servers: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}:11211
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
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
