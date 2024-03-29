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

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

conf-files:
  file.managed:
    - makedirs: True
    - template: jinja
    - defaults:
        cache_password: {{ pillar['cache']['maintenance_password'] }}
    - names:
{% if grains['os_family'] == 'Debian' %}
      - /etc/apt-cacher-ng/acng.conf:
        - source: salt://formulas/cache/files/acng.conf
      - /etc/apt-cacher-ng/security.conf:
        - source: salt://formulas/cache/files/security.conf
      - /etc/apt-cacher-ng/curl:
        - source: salt://formulas/cache/files/curl
{% elif grains['os_family'] == 'RedHat' %}
      - /root/acng.conf:
        - source: salt://formulas/cache/files/acng.conf
      - /root/security.conf:
        - source: salt://formulas/cache/files/security.conf
      - /root/curl:
        - source: salt://formulas/cache/files/curl
{% endif %}

get_centos_mirros:
  cmd.run:
{% if grains['os_family'] == 'Debian' %}
    - name: curl https://git.centos.org/centos/centos.org/raw/3dc5ae396b4fa849fc03fd07ed01d831b0de9ef8/f/_data/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/etc/apt-cacher-ng/centos_mirrors
    - creates: /etc/apt-cacher-ng/centos_mirrors
{% elif grains['os_family'] == 'RedHat' %}
    - name: curl https://git.centos.org/centos/centos.org/raw/3dc5ae396b4fa849fc03fd07ed01d831b0de9ef8/f/_data/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/root/centos_mirrors
    - creates: /root/centos_mirrors
{% endif %}

{% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
container_manage_cgroup:
  selinux.boolean:
    - value: 1
    - persist: True
{% endif %}

{% if grains['os_family'] == 'Debian' %}

apt-cacher-ng_service:
  service.running:
    - name: apt-cacher-ng
    - enable: True
    - watch:
      - file: conf-files
      - cmd: get_centos_mirros

{% for dir in ['data', 'logs'] %}
/opt/cache/windows/{{ dir }}:
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
      - /opt/cache/windows/data:/data/cache
      - /opt/cache/windows/logs:/data/logs
    - ports:
      - 80
      - 443
    - port_bindings:
      - 80:80
      - 443:443
    - require:
      - service: apache2_service
      - file: /opt/cache/windows/data
      - file: /opt/cache/windows/logs

# NOTE(chateaulav): should apply a better filter to target whatever ip is
#                   assigned as the management interface
lancachenet_dns:
  docker_container.running:
    - name: lancache-dns
    - image: lancachenet/lancache-dns:latest
    - restart_policy: unless-stopped
    - ports:
      - 53/udp
    - port_bindings:
      - 53:53/udp
    - environment:
      - UPSTREAM_DNS: {{ pillar['networking']['addresses']['float_dns'] }}
      - WSUSCACHE_IP: {{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - require:
      - service: systemd-resolved_service
      - docker_container: lancachenet_monolith

{% elif grains['os_family'] == 'RedHat' %}

/root/acng.dockerfile:
  file.managed:
    - source: salt://formulas/cache/files/acng.dockerfile

build acng container image:
  cmd.run:
    - name: buildah bud -t acng acng.dockerfile
    - onchanges:
      - file: /root/acng.dockerfile
      - file: conf-files

## working around https://github.com/containers/libpod/issues/4605 by temporarily removing volumes
## podman create -d -p 3142:3142 --name apt-cacher-ng --volume apt-cacher-ng:/var/cache/apt-cacher-ng acng
create acng container:
  cmd.run:
    - name: podman create -d -p 3142:3142 --name apt-cacher-ng acng
    - require:
      - cmd: build acng container image
    - unless:
      - podman container ls -a | grep -q apt-cacher-ng

/etc/systemd/system/apt-cacher-ng-container.service:
  file.managed:
    - source: salt://formulas/cache/files/apt-cacher-ng-container.service
    - mode: "0644"
    - require:
      - cmd: create acng container

apt-cacher-ng-container:
  service.running:
    - enable: True
    - require:
      - file: /etc/systemd/system/apt-cacher-ng-container.service
    - watch:
      - file: /etc/systemd/system/apt-cacher-ng-container.service

{% endif %}
