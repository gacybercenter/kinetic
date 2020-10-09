include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

make_designate_service:
  cmd.script:
    - source: salt://formulas/designate/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        designate_public_endpoint: {{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['path'] }}
        designate_service_password: {{ pillar ['designate']['designate_service_password'] }}

/bin/sh -c "designate-manage database sync" designate:
  cmd.run:
    - require:
      - file: /etc/designate/designate.conf
    - onchanges:
      - file: /etc/designate/designate.conf

/bin/sh -c "designate-manage pool update" designate:
  cmd.run:
    - require:
      - file: /etc/designate/pools.yaml
      - service: designate_api_service
      - service: designate_central_service
      - service: designate_mdns_service
      - service: designate_worker_service
      - service: designate_producer_service
    - onchanges:
      - file: /etc/designate/pools.yaml

/bin/sh -c "designate-manage tlds import --input_file /etc/designate/tlds.conf" designate:
  cmd.run:
    - require:
      - file: /etc/designate/tlds.conf
      - service: designate_api_service
      - service: designate_central_service
      - service: designate_mdns_service
      - service: designate_worker_service
      - service: designate_producer_service
    - onchanges:
      - file: /etc/designate/tlds.conf

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

/etc/designate/tlds.conf:
  file.managed:
    - source: salt://formulas/designate/files/tlds.conf

/etc/designate/designate.conf:
  file.managed:
    - source: salt://formulas/designate/files/designate.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://designate:{{ pillar['designate']['designate_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/designate'
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
        password: {{ pillar['designate']['designate_service_password'] }}
        listen_api: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}:9001
        designate_public_endpoint: {{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['designate']['configuration']['public_endpoint']['path'] }}
        coordination_server: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('G@role:memcached and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}:11211
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}

## Trying to write yaml in yaml via salt with correct indentation is basically impossible when using
## file.managed with the source directive.  Using contents is ugly, but it works.
/etc/designate/pools.yaml:
  file.managed:
    - template: jinja
    - contents: |
        - name: default
          description: Default Pool
          attributes: {}
          ns_records:
            - hostname: {{ grains['fqdn'] }}.
              priority: 1
          nameservers:
          {%- for host, addresses in salt['mine.get']('role:bind', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {% for address in addresses %}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
            - host: {{ address }}
              port: 53
              {%- endif -%}
            {% endfor %}
          {%- endfor %}
          targets:
          {%- for host, addresses in salt['mine.get']('role:bind', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {% for address in addresses %}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
            - type: bind9
              description: bind9 server
              masters:
              {%- for d_host, d_addresses in salt['mine.get']('role:designate', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
                {% for d_address in d_addresses %}
                  {%- if salt['network']['ip_in_subnet'](d_address, pillar['networking']['subnets']['management']) -%}
                - host: {{ d_address }}
                  port: 5354
                  {%- endif -%}
                {% endfor %}
              {%- endfor %}
              options:
                host: {{ address }}
                port: 53
                rndc_host: {{ address }}
                rndc_port: 953
                rndc_key_file: /etc/designate/rndc.key
              {%- endif -%}
            {% endfor %}
          {%- endfor %}

/etc/designate/rndc.key:
  file.managed:
    - contents_pillar: designate:designate_rndc_key
    - mode: 640
    - user: root
    - group: designate

designate_api_service:
  service.running:
    - name: designate-api
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: /etc/designate/designate.conf
      - file: /etc/designate/pools.yaml

designate_central_service:
  service.running:
    - name: designate-central
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: /etc/designate/designate.conf
      - file: /etc/designate/pools.yaml

designate_worker_service:
  service.running:
    - name: designate-worker
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: /etc/designate/designate.conf
      - file: /etc/designate/pools.yaml

designate_producer_service:
  service.running:
    - name: designate-producer
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: /etc/designate/designate.conf
      - file: /etc/designate/pools.yaml

designate_mdns_service:
  service.running:
    - name: designate-mdns
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: /etc/designate/designate.conf
      - file: /etc/designate/pools.yaml
