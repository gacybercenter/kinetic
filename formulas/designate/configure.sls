include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

designate-manage database sync:
  cmd.run:
    - runas: designate
    - require:
      - file: /etc/designate/designate.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

designate-manage pool update:
  cmd.run:
    - runas: designate
    - require:
      - file: /etc/designate/pools.yaml
      - service: designate_api_service
      - service: designate_central_service
      - service: designate_mdns_service
      - service: designate_worker_service
      - service: designate_producer_service
    - onchanges:
      - file: /etc/designate/pools.yaml

designate-manage tlds import --input_file /etc/designate/tlds.conf:
  cmd.run:
    - runas: designate
    - require:
      - file: /etc/designate/tlds.conf
      - service: designate_api_service
      - service: designate_central_service
      - service: designate_mdns_service
      - service: designate_worker_service
      - service: designate_producer_service
    - onchanges:
      - file: /etc/designate/tlds.conf

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/designate/tlds.conf:
  file.managed:
    - source: salt://formulas/designate/files/tlds.conf

/etc/designate/designate.conf:
  file.managed:
    - source: salt://formulas/designate/files/designate.conf
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='designate', database='designate') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        password: {{ pillar['designate']['designate_service_password'] }}
        listen_api: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}:9001
        designate_public_endpoint: {{ constructor.endpoint_url_constructor(project='designate', service='designate', endpoint='public') }}
        coordination_server: {{ constructor.spawnzero_ip_constructor(type='memcached', network='management') }}

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
