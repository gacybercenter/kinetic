## Copyright 2018 Augusta University
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
  - /formulas/common/fluentd/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

{% if salt['pillar.get']('tnsr:enabled', False) == True %}
/etc/haproxy/tnsr.crt:
  file.managed:
    - contents_pillar: tnsr_cert
    - mode: "0640"
    - user: root

/etc/haproxy/tnsr.pem:
  file.managed:
    - contents_pillar: tnsr_key
    - mode: "0640"
    - user: root

tnsr_nat_updates:
  tnsr.nat_updated:
    - name: tnsr_nat_updates
    - new_entries:
      - transport-protocol: "any"
        local-address: "{{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}"
        local-port: "any"
        external-address: "{{ pillar['haproxy']['external_address'] }}"
        external-port: "any"
        route-table-name: "{{ pillar['haproxy']['route_table'] }}"
    - cert: /etc/haproxy/tnsr.crt
    - key: /etc/haproxy/tnsr.pem
    - hostname: {{ pillar['tnsr']['endpoint'] }}
    - cacert: False
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - require:
      - file: /etc/haproxy/tnsr.crt
      - file: /etc/haproxy/tnsr.pem
    - onlyif:
      - salt-call dnsutil.A '{{ pillar['tnsr']['endpoint'] }}'

tnsr_local_zones_updates:
  tnsr.unbound_updated:
    - name: tnsr_local_zones_updates
    - type: "local-zone"
    - new_zones:
      - zone-name: "{{ pillar['haproxy']['zone_name'] }}"
        type: "transparent"
        hosts:
          host:
            - ip-address:
              - "{{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}"
              host-name: "{{ pillar['haproxy']['sub_zone_name'].split('.')[0] }}"
      - zone-name: "{{ pillar['haproxy']['sub_zone_name'] }}"
        type: "transparent"
        hosts:
          host:
            - ip-address:
              - "{{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}"
              host-name: "{{ pillar['haproxy']['dashboard_domain'].split('.')[0] }}"
            - ip-address:
              - "{{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}"
              host-name: "{{ pillar['haproxy']['console_domain'].split('.')[0] }}"
    - cert: /etc/haproxy/tnsr.crt
    - key: /etc/haproxy/tnsr.pem
    - hostname: {{ pillar['tnsr']['endpoint'] }}
    - cacert: False
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - require:
      - file: /etc/haproxy/tnsr.crt
      - file: /etc/haproxy/tnsr.pem
    - onlyif:
      - salt-call dnsutil.A '{{ pillar['tnsr']['endpoint'] }}'

  {% if salt['mine.get']('role:bind', 'network.ip_addrs', tgt_type='grain')|length != 0 %}
    {% set bind_ips = [] %}
    {% for address in salt['mine.get']('role:bind', 'network.ip_addrs', tgt_type='grain') %}
      {{ bind_ips.append( address ) }}
    {% endfor %}
    {% do salt.log.info("bind ips: "+bind_ips) %}
tnsr_forward_zones_updates:
  tnsr.unbound_updated:
    - name: tnsr_forward_zones_updates
    - type: "forward-zone"
    - new_zones:
      - zone-name: "{{ pillar['designate']['tld'] }}"
        forward-addresses:
          address:
    {% for address in bind_ips | address('int') | sort %}
            - ip-address: "{{ address }}"
    {% endfor %}
    - cert: /etc/haproxy/tnsr.crt
    - key: /etc/haproxy/tnsr.pem
    - hostname: {{ pillar['tnsr']['endpoint'] }}
    - cacert: False
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - require:
      - file: /etc/haproxy/tnsr.crt
      - file: /etc/haproxy/tnsr.pem
    - onlyif:
      - salt-call dnsutil.A '{{ pillar['tnsr']['endpoint'] }}'
  {% endif %}
{% endif %}

{% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
haproxy_connect_any:
  selinux.boolean:
    - value: True
    - persist: True
    - require:
      - sls: /formulas/haproxy/install
{% endif %}

acme_certs:
  acme.cert:
    - name: {{ pillar['haproxy']['dashboard_domain'] }}
    - aliases:
      - {{ pillar['haproxy']['console_domain'] }}
      - {{ pillar['haproxy']['guacamole_domain'] }}
    - email: {{ pillar['haproxy']['acme_email'] }}
    - renew: 14
{% if salt['pillar.get']('development:test_certs', False) == True %}
    - test_cert: True
{% endif %}
{% if salt['pillar.get']('tnsr:enabled', False) == True %}
    - require:
      - tnsr: tnsr_nat_updates
      - tnsr: tnsr_local_zones_updates
{% endif %}

create_master_pem:
  cmd.run:
    - name: cat /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/fullchain.pem /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/privkey.pem > /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/master.pem
    - creates: /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/master.pem
    - require:
      - acme: acme_certs

create_dhparams_file:
  cmd.run:
    - name: openssl dhparam -out /etc/haproxy/dhparams.pem 2048
    - unless: ls /etc/haproxy/dhparams.pem

/etc/haproxy/haproxy.cfg:
  file.managed:
    - source: salt://formulas/haproxy/files/haproxy.cfg
    - template: jinja
    - defaults:
        syslog: 127.0.0.1:5514
        hostname: {{ grains['id'] }}
        management_ip_address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
        console_domain:  {{ pillar['haproxy']['console_domain'] }}
        guacamole_domain:  {{ pillar['haproxy']['guacamole_domain'] }}
        keystone_hosts: {{ constructor.haproxy_listener_constructor(role='keystone', port='5000')|yaml_encode }}
        glance_api_hosts: {{ constructor.haproxy_listener_constructor(role='glance', port='9292')|yaml_encode }}
        nova_compute_api_hosts: {{ constructor.haproxy_listener_constructor(role='nova', port='8774')|yaml_encode }}
        nova_metadata_api_hosts: {{ constructor.haproxy_listener_constructor(role='nova', port='8775')|yaml_encode }}
        placement_api_hosts: {{ constructor.haproxy_listener_constructor(role='placement', port='8778')|yaml_encode }}
        nova_spiceproxy_hosts: {{ constructor.haproxy_listener_constructor(role='nova', port='6082')|yaml_encode }}
        nova_nsproxy_hosts: {{ constructor.haproxy_listener_constructor(role='nova', port='6083')|yaml_encode }}
        dashboard_hosts: {{ constructor.haproxy_listener_constructor(role='horizon', port='80')|yaml_encode }}
        neutron_api_hosts: {{ constructor.haproxy_listener_constructor(role='neutron', port='9696')|yaml_encode }}
        heat_api_hosts: {{ constructor.haproxy_listener_constructor(role='heat', port='8004')|yaml_encode }}
        cinder_api_hosts: {{ constructor.haproxy_listener_constructor(role='cinder', port='8776')|yaml_encode }}
        heat_api_cfn_hosts: {{ constructor.haproxy_listener_constructor(role='heat', port='8000')|yaml_encode }}
        designate_api_hosts: {{ constructor.haproxy_listener_constructor(role='designate', port='9001')|yaml_encode }}
        swift_hosts: {{ constructor.haproxy_listener_constructor(role='swift', port='7480')|yaml_encode }}
        zun_api_hosts: {{ constructor.haproxy_listener_constructor(role='zun', port='9517')|yaml_encode }}
        zun_wsproxy_hosts: {{ constructor.haproxy_listener_constructor(role='zun', port='6784')|yaml_encode }}
        barbican_hosts: {{ constructor.haproxy_listener_constructor(role='barbican', port='9311')|yaml_encode }}
        magnum_hosts: {{ constructor.haproxy_listener_constructor(role='magnum', port='9511')|yaml_encode }}
        sahara_hosts: {{ constructor.haproxy_listener_constructor(role='sahara', port='8386')|yaml_encode }}
        manila_hosts: {{ constructor.haproxy_listener_constructor(role='manila', port='8786')|yaml_encode }}
        mysql_hosts: {{ constructor.haproxy_listener_constructor(role='mysql', port='3306')|yaml_encode }}
        guacamole_hosts: {{ constructor.haproxy_listener_constructor(role='guacamole', port='8080')|yaml_encode }}
        cyborg_hosts: {{ constructor.haproxy_listener_constructor(role='cyborg', port='6666')|yaml_encode }}

haproxy_service_watch:
  service.running:
    - name: haproxy
    - reload: true
    - watch:
      - file: /etc/haproxy/haproxy.cfg
      - acme: acme_certs
