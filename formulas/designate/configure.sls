include:
  - formulas/designate/install
  - formulas/common/base
  - formulas/common/networking

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
    - unless:
      - /bin/sh -c "designate-manage database version" designate | grep -q "Current: 102"
    - require:
      - file: /etc/designate/designate.conf

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

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

/etc/designate/tlds.conf:
  file.managed:
    - source: salt://formulas/designate/files/tlds.conf

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
          {%- for host, addresses in salt['mine.get']('role:bind', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
            - host: {{ address }}
              port: 53
              {% endif %}
            {%- endfor -%}
          {% endfor -%}

/etc/designate/rndc.key:
  file.managed:
    - contents_pillar: designate:designate_rndc_key
    - mode: 640
    - user: root
{% if grains['os_family'] == 'Debian' %}
    - group: bind
{% elif grains['os_family'] == 'RedHat' %}
    - group: named
{% endif %}

designate_api_service:
  service.running:
    - name: designate-api
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_central_service:
  service.running:
    - name: designate-central
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_worker_service:
  service.running:
    - name: designate-worker
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_producer_service:
  service.running:
    - name: designate-producer
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

designate_mdns_service:
  service.running:
    - name: designate-mdns
    - enable: true
    - watch:
      - file: /etc/designate/designate.conf

/bin/sh -c "designate-manage pool update" designate:
  cmd.run:
    - onchanges:
      - file: /etc/designate/pools.yaml

/bin/sh -c "designate-manage tlds import --input_file /etc/designate/tlds.conf" designate:
  cmd.run:
    - onchanges:
      - file: /etc/designate/tlds.conf
