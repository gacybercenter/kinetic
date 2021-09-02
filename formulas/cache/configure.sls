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

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

apt-cacher-ng-conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/apt-cacher-ng/acng.conf
{% elif grains['os_family'] == 'RedHat' %}
    - name: /root/acng.conf
{% endif %}
    - source: salt://formulas/cache/files/acng.conf

security-conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/apt-cacher-ng/security.conf
{% elif grains['os_family'] == 'RedHat' %}
    - name: /root/security.conf
{% endif %}
    - contents: |
        AdminAuth: acng:{{ pillar['cache']['maintenance_password'] }}

curl-conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/apt-cacher-ng/curl
{% elif grains['os_family'] == 'RedHat' %}
    - name: /root/curl
{% endif %}
    - makedirs: True
    - contents: |
        user = acng:{{ pillar['cache']['maintenance_password'] }}

get_centos_mirros:
  cmd.run:
{% if grains['os_family'] == 'Debian' %}
    - name: curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/etc/apt-cacher-ng/centos_mirrors
    - creates: /etc/apt-cacher-ng/centos_mirrors
{% elif grains['os_family'] == 'RedHat' %}
    - name: curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/root/centos_mirrors
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
      - file: apt-cacher-ng-conf
      - file: security-conf
      - cmd: get_centos_mirros

{% elif grains['os_family'] == 'RedHat' %}

/root/acng.dockerfile:
  file.managed:
    - source: salt://formulas/cache/files/acng.dockerfile

build acng container image:
  cmd.run:
    - name: buildah bud -t acng acng.dockerfile
    - onchanges:
      - file: /root/acng.dockerfile
      - file: apt-cacher-ng-conf
      - file: security-conf
      - file: curl-conf

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
