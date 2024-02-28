## Copyright 2020 Augusta University
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

## if the number of cache endpoints is nonzero, iterate through all cache endpoints and if returned IP is in management network,
## use it when constructing the proxy configuration
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for address in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last () if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}

include:
  - /formulas/common/salt/repo
  - /formulas/common/fluentd/repo

systemd-resolved_service:
  service.dead:
    - name: systemd-resolved
    - unless:
      - 'systemctl status systemd-resolved.service | grep -q "Active: inactive (dead)"'

/run/systemd/resolve/resolv.conf:
  file.managed:
    - makedirs: True
    - contents: |
        nameserver {{ address }}
    - require:
      - service: systemd-resolved_service

update_sources_list:
  file.managed:
    - makedirs: True
    - template: jinja
    - defaults:
        ubuntu_name: {{ pillar['ubuntu']['name'] }}
        openstack_version: {{ pillar['openstack']['version'] }}
      {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
        {{ repo | replace('-', '_') }}: http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }}
      {% endfor %}
    - names:
      {% if grains['type'] == 'arm' %}
      - /etc/apt/sources.list:
        - source: salt://formulas/common/sources/files/sources-arm.list
      {% else %}
      - /etc/apt/sources.list:
        - source: salt://formulas/common/sources/files/sources.list
      {% endif %}
  {% endfor %}
{% endif %}

{% if salt['grains.get']('upgraded') != True %}
update_all:
  pkg.uptodate:
    - refresh: true
    - dist_upgrade: True

upgraded:
  grains.present:
    - value: True
    - require:
      - update_all
{% endif %}

{% if grains['virtual'] == "physical" %}
## temporary patch for pyopenssl that exists on physical nodes
## https://stackoverflow.com/questions/73830524/attributeerror-module-lib-has-no-attribute-x509-v-flag-cb-issuer-check
OpenSSL_dir_remove:
  file.absent:
    - name: /usr/lib/python3/dist-packages/OpenSSL

pyOpenSSL_dir_remove:
  file.absent:
    - name: /usr/lib/python3/dist-packages/pyOpenSSL-21.0.0.egg-info

pyghmi_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - pyopenssl
      - pyghmi
    - require:
      - OpenSSL_dir_remove
      - pyOpenSSL_dir_remove
      - pin_pip_version
  pkg.installed:
    - pkgs:
      - ipmitool
      - vim

pyghmi_salt_pip:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: True
    - pkgs:
      - pyopenssl
      - pyghmi
    - require:
      - pyghmi_pip
      - pin_salt_pip_version

rdma-core:
  pkg.installed:
    - onlyif:
      - lshw | grep -qi rdma
{% endif %}
