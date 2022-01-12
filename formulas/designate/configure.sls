## Copyright 2019 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

designate-manage database sync:
  cmd.run:
    - runas: designate
    - require:
      - file: conf-files
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

### this is a bit odd that it just started causing problems
### Starting the services here because it does not seem to
### starting the service before trying to update the pools

# restart_designate_central_service:
#   cmd.run:
#     - name: systemctl restart designate-central.service
#     - require:
#       - cmd: designate-manage database sync

designate-manage pool update:
  cmd.run:
    - runas: designate
    - require:
      - file: /etc/designate/pools.yaml
      - service: designate_central_service
    - onchanges:
      - file: /etc/designate/pools.yaml

designate-manage tlds import --input_file /etc/designate/tlds.conf:
  cmd.run:
    - runas: designate
    - require:
      - file: /etc/designate/tlds.conf
      - cmd: designate-manage pool update
    - onchanges:
      - file: /etc/designate/tlds.conf

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

conf-files:
  file.managed:
    - makedirs: True
    - template: jinja
    - defaults:
        tld: {{ pillar['designate']['tld'] }}
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='designate', database='designate') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        designate_password: {{ pillar['designate']['designate_service_password'] }}
        listen_api: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}:9001
        designate_public_endpoint: {{ constructor.endpoint_url_constructor(project='designate', service='designate', endpoint='public') }}
        coordination_server: {{ constructor.spawnzero_ip_constructor(type='memcached', network='management') }}:11211
    - names:
      - /etc/designate/tlds.conf:
        - source: salt://formulas/designate/files/tlds.conf
      - /etc/designate/designate.conf:
        - source: salt://formulas/designate/files/designate.conf
      - /etc/designate/policy.yaml:
        - source: salt://formulas/designate/files/policy.yaml

## Trying to write yaml in yaml via salt with correct indentation is basically impossible when using
## file.managed with the source directive.  Using contents is ugly, but it works.
## To do: write a macro to be called in constructor and source from yaml instead writing yaml with yaml
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
    - mode: "0640"
    - user: root
    - group: designate

designate_api_service:
  service.running:
    - name: designate-api
    - enable: True
    - reload: True
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: conf-files
      - file: /etc/designate/pools.yaml

designate_central_service:
  service.running:
    - name: designate-central
    - enable: True
    - reload: True
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: conf-files
      - file: /etc/designate/pools.yaml

designate_worker_service:
  service.running:
    - name: designate-worker
    - enable: True
    - reload: True
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: conf-files
      - file: /etc/designate/pools.yaml

designate_producer_service:
  service.running:
    - name: designate-producer
    - enable: True
    - reload: True
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: conf-files
      - file: /etc/designate/pools.yaml

designate_mdns_service:
  service.running:
    - name: designate-mdns
    - enable: True
    - reload: True
    - watch:
      - file: /etc/designate/designate.conf
    - require:
      - file: conf-files
      - file: /etc/designate/pools.yaml
