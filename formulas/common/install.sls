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

set_package_proxy:
  file.managed:
    {% if grains['os_family'] == 'Debian' %}
    - name: /etc/apt/apt.conf.d/02proxy
    - contents: |
        Acquire::http { Proxy "http://{{ address }}:3142"; };
    {% elif grains['os_family'] == 'RedHat' %}
    - name: /etc/yum.conf
    - contents: |
        [main]
        gpgcheck=1
        installonly_limit=3
        clean_requirements_on_remove=True
        best=True
        skip_if_unavailable=False
        proxy=http://{{ address }}:3142
    {% endif %}
    {% if salt['network']['connect'](host=salt['grains.get']('cache_target', '127.0.0.1'), port="3142")['result'] == True %}
    - replace: False
    {% endif %}
    - onlyif:
      - fun: network.connect
        host: {{ address }}
        port: 3142

cache_target:
  grains.present:
    - value: {{ address }}
    - onchanges:
      - file: set_package_proxy
  {% endfor %}
{% endif %}

{% if salt['grains.get']('upgraded') != True %}
update_all:
  pkg.uptodate:
    - refresh: true
  {% if grains['os_family'] == 'Debian' %}
    - dist_upgrade: True
  {% endif %}

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

rdma-core:
  pkg.installed:
    - onlyif:
      - lshw | grep -qi rdma
{% endif %}
