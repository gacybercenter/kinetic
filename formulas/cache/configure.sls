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
{% set address = salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['management'])[0] %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}


{% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
container_manage_cgroup:
  selinux.boolean:
    - value: 1
    - persist: True
{% endif %}

{% if grains['os_family'] == 'Debian' %}

/etc/cache/tnsr.crt:
  file.managed:
    - makedirs: True
    - contents_pillar: tnsr_cert
    - mode: "0640"
    - user: root

/etc/cache/tnsr.pem:
  file.managed:
    - makedirs: True
    - contents_pillar: tnsr_key
    - mode: "0640"
    - user: root

tnsr_name_resolution:
  cmd.run:
    - name: salt-call dnsutil.A '{{ pillar['tnsr']['endpoint'] }}'
    - retry:
        attempts: 5
        delay: 10
        splay: 5

tnsr_local_zones_updates:
  tnsr.unbound_updated:
    - name: tnsr_local_zones_updates
    - type: "local-zone"
    - new_zones:
      - zone-name: "{{ pillar['haproxy']['sub_zone_name'] }}"
        type: "transparent"
        hosts:
          host:
            - ip-address:
              - "{{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}"
              host-name: "cache"
    - cert: /etc/cache/tnsr.crt
    - key: /etc/cache/tnsr.pem
    - hostname: {{ pillar['tnsr']['endpoint'] }}
    - cacert: False
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - require:
      - file: /etc/cache/tnsr.crt
      - file: /etc/cache/tnsr.pem
      - cmd: tnsr_name_resolution

{% set cache_dns = 'cache.' + pillar['haproxy']['sub_zone_name'] %}

{% for dir in ['data', 'logs'] %}
/cache/{{ dir }}:
  file.directory:
    - user: root
    - group: root
    - mode: "0755"
    - makedirs: True
{% endfor %}

systemd-resolved_service:
  service.dead:
    - name: systemd-resolved
    - unless:
      - 'systemctl status systemd-resolved.service | grep -q "Active: inactive (dead)"'

/run/systemd/resolve/resolv.conf:
  file.managed:
    - makedirs: True
    - contents: |
        nameserver {{ pillar['networking']['addresses']['float_dns'] }}
    - require:
      - service: systemd-resolved_service

lancachenet_monolith:
  docker_container.running:
    - name: lancache
    - image: lancachenet/monolithic:latest
    - restart_policy: unless-stopped
    - volumes:
      - /cache/data:/data/cache
      - /cache/logs:/data/logs
    - ports:
      - {{ pillar['cache']['lancache']['http_port'] }}
      - {{ pillar['cache']['lancache']['https_port'] }}
    - port_bindings:
      - {{ pillar['cache']['lancache']['http_port'] }}:80
      - {{ pillar['cache']['lancache']['https_port'] }}:443
    - environment:
      - UPSTREAM_DNS: {{ pillar['networking']['addresses']['float_dns'] }}
      - WSUSCACHE_IP: {{ address }}
      - LINUXCACHE_IP: {{ address }}
    - require:
      - file: /cache/data
      - file: /cache/logs

lancachenet_dns:
  docker_container.running:
    - name: lancache-dns
    - image: lancachenet/lancache-dns:latest
    - restart_policy: unless-stopped
    - ports:
      - {{ pillar['cache']['lancache']['dns_port'] }}/udp
    - port_bindings:
      - {{ pillar['cache']['lancache']['dns_port'] }}:53/udp
    - environment:
      - UPSTREAM_DNS: {{ pillar['networking']['addresses']['float_dns'] }}
      - WSUSCACHE_IP: {{ address }}
      - LINUXCACHE_IP: {{ address }}
    - require:
      - service: systemd-resolved_service
      - docker_container: lancachenet_monolith

nexusproxy_update_user_password:
  nexusproxy.update_user_password:
    - name: nexusproxy_update_user_password
    - host: "http://{{ address }}"
    - port: "{{ pillar['cache']['nexusproxy']['port'] }}"
    - username: "{{ pillar['cache']['nexusproxy']['username'] }}"
    - password: "{{ grains['original_password'] }}"
    - user:  "{{ pillar['cache']['nexusproxy']['username'] }}"
    - new_password: "{{ pillar['nexusproxy']['nexusproxy_password'] }}"
    - onlyif:
      - docker ps |grep nexusproxy && docker exec nexusproxy ls -al /nexus-data/ | grep -q 'admin.password'
      - fun: network.connect
        host: {{ address }}
        port: {{ pillar['cache']['nexusproxy']['port'] }}

{% for repo in pillar['cache']['nexusproxy']['repositories'] %}
{{ repo }}_sleep:
  module.run:
    - test.sleep:
      - length: 5
    - onlyif:
      - salt-call nexusproxy.list_repository "http://{{ address }}" "{{ pillar['cache']['nexusproxy']['port'] }}" "{{ pillar['cache']['nexusproxy']['username'] }}" "{{ pillar['nexusproxy']['nexusproxy_password'] }}" "{{ repo }}" | grep -q "{{ repo }}"
    - unless:
      - docker exec nexusproxy ls -al /nexus-data/ | grep -q 'admin.password'

{{ repo }}_add_proxy_repository:
  nexusproxy.add_proxy_repository:
    - name: "{{ repo }}"
    - host: "http://{{ address }}"
    - port: "{{ pillar['cache']['nexusproxy']['port'] }}"
    - username: "{{ pillar['cache']['nexusproxy']['username'] }}"
    - password: "{{ pillar['nexusproxy']['nexusproxy_password'] }}"
    - repoType: "{{ pillar['cache']['nexusproxy']['repositories'][repo]['type'] }}"
    - remoteUrl: "{{ pillar['cache']['nexusproxy']['repositories'][repo]['url'] }}"
    - require:
      - module: {{ repo }}_sleep
    - onlyif:
      - fun: network.connect
        host: {{ address }}
        port: {{ pillar['cache']['nexusproxy']['port'] }}
    - unless:
      - docker exec nexusproxy ls -al /nexus-data/ | grep -q 'admin.password'
{% endfor %}
{% endif %}