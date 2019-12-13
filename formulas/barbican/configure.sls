include:
  - formulas/barbican/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

make_barbican_service:
  cmd.script:
    - source: salt://formulas/barbican/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        barbican_internal_endpoint: {{ pillar ['openstack_services']['barbican']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['barbican']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['barbican']['configuration']['internal_endpoint']['path'] }}
        barbican_public_endpoint: {{ pillar ['openstack_services']['barbican']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['barbican']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['barbican']['configuration']['public_endpoint']['path'] }}
        barbican_admin_endpoint: {{ pillar ['openstack_services']['barbican']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['barbican']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['barbican']['configuration']['admin_endpoint']['path'] }}
        barbican_service_password: {{ pillar ['barbican']['barbican_service_password'] }}

barbican-manage db upgrade:
  cmd.run:
    - runas: barbican
    - require:
      - file: /etc/barbican/barbican.conf

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/barbican/barbican.conf:
  file.managed:
    - source: salt://formulas/barbican/files/barbican.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        transport_url: transport_url = rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address[0] }}
{% endfor %}
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'sql_connection = mysql+pymysql://barbican:{{ pillar['barbican']['barbican_mysql_password'] }}@{{ address[0] }}/barbican'
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        memcached_servers:
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {% address+":11211" %}
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        password: {{ pillar['barbican']['barbican_service_password'] }}
        kek: kek = '{{ pillar['barbican']['simplecrypto_key'] }}'
        host_href: host_href = {{ pillar ['openstack_services']['barbican']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['barbican']['configuration']['public_endpoint']['port'] }}

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
