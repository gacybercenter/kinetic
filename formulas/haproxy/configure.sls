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

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

### Gateway configuration
{% if salt['pillar.get']('danos:enabled', False) == True %}
set haproxy group:
  danos.set_resourcegroup:
    - name: haproxy-{{ pillar['haproxy']['group'] }}
    - type: address-group
    - description: current haproxy servers for {{ pillar['haproxy']['group'] }}
    - values:
      - {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - username: {{ pillar['danos']['username'] }}
    - password: {{ pillar['danos_password'] }}
  {% if salt['pillar.get']('danos:endpoint', "gateway") == "gateway" %}
    - host: {{ grains['ip4_gw'] }}
  {% else %}
    - host: {{ pillar['danos']['endpoint'] }}
  {% endif %}

set haproxy static-mapping:
  danos.set_statichostmapping:
    - name: {{ pillar['haproxy']['dashboard_domain'] }}
    - address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - aliases:
      - {{ pillar['haproxy']['console_domain'] }}
      - {{ pillar['haproxy']['guacamole_domain'] }}
    - username: {{ pillar['danos']['username'] }}
    - password: {{ pillar['danos_password'] }}
  {% if salt['pillar.get']('danos:endpoint', "gateway") == "gateway" %}
    - host: {{ grains['ip4_gw'] }}
  {% else %}
    - host: {{ pillar['danos']['endpoint'] }}
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

haproxy_service_stop:
  service.dead:
    - name: haproxy

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
{% if salt['pillar.get']('danos:enabled', False) == True %}
    - require:
      - service: haproxy_service_stop
      - danos: set haproxy group
      - danos: set haproxy static-mapping
{% endif %}

create_master_pem:
  cmd.run:
    - name: cat /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/fullchain.pem /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/privkey.pem > /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/master.pem
    - creates: /etc/letsencrypt/live/{{ pillar['haproxy']['dashboard_domain'] }}/master.pem
    - require:
      - acme: acme_certs

/etc/haproxy/haproxy.cfg:
  file.managed:
    - source: salt://formulas/haproxy/files/haproxy.cfg
    - template: jinja
{% if salt['pillar.get']('syslog_url', False) == False %}
  {% for host, addresses in salt['mine.get']('role:graylog', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
    {% for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
    - context:
        syslog: {{ address }}:5514
    {% endfor %}
  {% endfor %}
{% endif %}
    - defaults:
{% if salt['pillar.get']('syslog_url', False) != False %}
        syslog: {{ pillar['syslog_url'] }}
{% else %}
        syslog: 127.0.0.1:5514
{% endif %}
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

haproxy_service_watch:
  service.running:
    - name: haproxy
    - reload: true
    - watch:
      - file: /etc/haproxy/haproxy.cfg
      - acme: acme_certs
