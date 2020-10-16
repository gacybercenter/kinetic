include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

barbican-manage db upgrade:
  cmd.run:
    - runas: barbican
    - require:
      - file: /etc/barbican/barbican.conf

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

  {% from 'formulas/common/macros/spawn.sls' import check_spawnzero_status with context %}
    {{ check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/barbican/barbican.conf:
  file.managed:
    - source: salt://formulas/barbican/files/barbican.conf
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
        sql_connection_string: 'sql_connection = mysql+pymysql://barbican:{{ pillar['barbican']['barbican_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/barbican'
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
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
