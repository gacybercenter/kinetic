include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

make_sahara_service:
  cmd.script:
    - source: salt://formulas/sahara/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        sahara_internal_endpoint: {{ pillar ['openstack_services']['sahara']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['sahara']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['sahara']['configuration']['internal_endpoint']['path'] }}
        sahara_public_endpoint: {{ pillar ['openstack_services']['sahara']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['sahara']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['sahara']['configuration']['public_endpoint']['path'] }}
        sahara_admin_endpoint: {{ pillar ['openstack_services']['sahara']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['sahara']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['sahara']['configuration']['admin_endpoint']['path'] }}
        sahara_service_password: {{ pillar ['sahara']['sahara_service_password'] }}

sahara-db-manage --config-file /etc/sahara/sahara.conf upgrade head:
  cmd.run:
    - runas: sahara
    - require:
      - file: /etc/sahara/sahara.conf

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

  {% from 'formulas/common/macros/spawn.sls' import check_spawnzero_status with context %}
    {{ check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/sahara/sahara.conf:
  file.managed:
    - source: salt://formulas/sahara/files/sahara.conf
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
        connection: mysql+pymysql://sahara:{{ pillar['sahara']['sahara_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/sahara
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}
        memcached_servers: |
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}:11211
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
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
