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


{% for dir in ['data', 'logs'] %}
/cache/{{ dir }}:
  file.directory:
    - user: root
    - group: root
    - mode: "0755"
    - makedirs: True
{% endfor %}

apache2_service:
  service.dead:
    - name: apache2
    - enable: false

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
      - CACHE_DOMAINS_REPO: {{ pillar['cache']['lancache']['cache_domains']['repo'] }}
      - CACHE_DOMAINS_BRANCH:  {{ pillar['cache']['lancache']['cache_domains']['branch'] }}
    - require:
      - service: apache2_service
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
      - CACHE_DOMAINS_REPO: {{ pillar['cache']['lancache']['cache_domains']['repo'] }}
      - CACHE_DOMAINS_BRANCH:  {{ pillar['cache']['lancache']['cache_domains']['branch'] }}
    - require:
      - service: systemd-resolved_service
      - docker_container: lancachenet_monolith

/etc/nexus/admin.password:
  file.managed:
    - replace: False
    - makedirs: True

nexusproxy:
  docker_container.running:
    - name: nexusproxy
    - image: sonatype/nexus3:latest
    - restart_policy: unless-stopped
    - ports:
      - 8081
    - port_bindings:
      - {{ pillar['cache']['nexusproxy']['port'] }}:8081

nexusproxy_startup_sleep:
  module.run:
    - test.sleep:
      - seconds: 60
    - require:
      - docker_container: nexusproxy

nexusproxy_connection:
  module.run:
    - network.connect:
      - host: {{ address }}
      - port: {{ pillar['cache']['nexusproxy']['port'] }}
    - retry:
      - attempts: 30
      - delay: 10
    - require:
      - docker_container: nexusproxy
      - module: nexusproxy_startup_sleep

admin.password:
  cmd.run:
    - name: docker exec nexusproxy cat /nexus-data/admin.password
    - require:
      - docker_container: nexusproxy
    - onlyif:
      - docker ps | grep nexusproxy && docker exec nexusproxy ls -al /nexus-data/ | grep -q 'admin.password'

nexusproxy_update_user_password:
  nexusproxy.update_user_password:
    - name: nexusproxy_update_user_password
    - host: {{ address }}
    - port: {{ pillar['cache']['nexusproxy']['port'] }}
    - username: {{ pillar['cache']['nexusproxy']['username'] }}
    - password: {{ salt['cmd.run']('cat /etc/nexus/admin.password') }}
    - user:  {{ pillar['cache']['nexusproxy']['username'] }}
    - new_password: {{ pillar['nexusproxy']['nexusproxy_password'] }}
    - require:
      - file: /etc/nexus/admin.password
      - cmd: admin.password
      - docker_container: nexusproxy
      - module: nexusproxy_startup_sleep
      - module: nexusproxy_connection
    - onlyif:
      - docker ps |grep nexusproxy && docker exec nexusproxy ls -al /nexus-data/ | grep -q 'admin.password'
      - fun: network.connect
        host: {{ address }}
        port: {{ pillar['cache']['nexusproxy']['port'] }}

{% for repo in pillar['cache']['nexusproxy']['repositories'] %}
{{ repo }}_add_proxy_repository:
  nexusproxy.add_proxy_repository:
    - name: {{ repo }}
    - host: {{ address }}
    - port: {{ pillar['cache']['nexusproxy']['port'] }}
    - username: {{ pillar['cache']['nexusproxy']['username'] }}
    - password: {{ pillar['nexusproxy']['nexusproxy_password'] }}
    - repoType: {{ pillar['cache']['nexusproxy']['repositories'][repo]['type'] }}
    - remoteUrl: {{ pillar['cache']['nexusproxy']['repositories'][repo]['url'] }}
    - require:
      - docker_container: nexusproxy
      - module: nexusproxy_startup_sleep
      - module: nexusproxy_connection
    - onlyif:
      - fun: network.connect
        host: {{ address }}
        port: {{ pillar['cache']['nexusproxy']['port'] }}
    - unless:
      - docker exec nexusproxy ls -al /nexus-data/ | grep -q 'admin.password'
{% endfor %}
{% endif %}