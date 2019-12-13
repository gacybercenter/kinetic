include:
  - formulas/manila/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

make_manila_service:
  cmd.script:
    - source: salt://formulas/manila/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        manila_internal_endpoint_v1: {{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['v1_path'] }}
        manila_public_endpoint_v1: {{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['v1_path'] }}
        manila_admin_endpoint_v1: {{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['v1_path'] }}
        manila_internal_endpoint_v2: {{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['internal_endpoint']['v2_path'] }}
        manila_public_endpoint_v2: {{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['public_endpoint']['v2_path'] }}
        manila_admin_endpoint_v2: {{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['manila']['configuration']['admin_endpoint']['v2_path'] }}
        manila_service_password: {{ pillar ['manila']['manila_service_password'] }}

manila-manage db sync:
  cmd.run:
    - runas: manila
    - require:
      - file: /etc/manila/manila.conf

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

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
{% for server, addresses in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        sql_connection_string: 'connection = mysql+pymysql://manila:{{ pillar['manila']['manila_mysql_password'] }}@{{ address }}/manila'
    {%- endif -%}
  {%- endfor -%}
{% endfor %}
{% for server, addresses in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address }}
    {%- endif -%}
  {%- endfor -%}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
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
        password: {{ pillar['manila']['manila_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
{% if salt['mine.get']('type:share', 'network.ip_addrs', tgt_type='grain')|length %}
  {% for server, addresses in salt['mine.get']('type:share', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
    {%- for address in addresses -%}
      {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['public']) %}
        ganesha_ip: {{ address }}
      {%- endif -%}
    {%- endfor -%}
  {% endfor %}
{% else %}
        ganesha_ip: 127.0.0.1
{% endif %}

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
