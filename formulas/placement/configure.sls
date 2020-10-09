include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

make_placement_service:
  cmd.script:
    - source: salt://formulas/placement/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        placement_internal_endpoint: {{ pillar ['openstack_services']['placement']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['placement']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['placement']['configuration']['internal_endpoint']['path'] }}
        placement_public_endpoint: {{ pillar ['openstack_services']['placement']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['placement']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['placement']['configuration']['public_endpoint']['path'] }}
        placement_admin_endpoint: {{ pillar ['openstack_services']['placement']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['placement']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['placement']['configuration']['admin_endpoint']['path'] }}
        placement_service_password: {{ pillar ['placement']['placement_service_password'] }}

placement-manage db sync:
  cmd.run:
    - runas: placement
    - require:
      - file: /etc/placement/placement.conf

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endif %}

/etc/placement/placement.conf:
  file.managed:
    - source: salt://formulas/placement/files/placement.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://placement:{{ pillar['placement']['placement_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/placement'
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
