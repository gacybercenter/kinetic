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
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}
    {% if pillar['neutron']['backend'] == "linuxbridge" %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - neutron-server
      - neutron-plugin-ml2
      - python3-openstackclient
      - python3-tornado
      - python3-etcd3gw

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

tornado_pip:
  pip.installed:
    - name: tornado
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

etcd3gw_pip:
  pip.installed:
    - name: etcd3gw
    - bin_env: 'usr/bin/pip3'
    - reload_modules: True

neutron_packages_salt-pip:
  pip.installed:
    -bin_env: '/use/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -openstackclient
      -tornado
      -etcd3gw
    -require:
      -neutron_packages

  {% elif pillar['neutron']['backend'] == "openvswitch" %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - neutron-server
      - neutron-plugin-ml2
      - python3-openstackclient
      - python3-tornado

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

tornado_pip:
  pip.installed:
    - name: tornado
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

neutron_packages_salt-pip:
  pip.installed:
    -bin_env: '/use/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -openstackclient
      -tornado
    -require:
      -neutron_packages

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - neutron-server
      - neutron-plugin-ml2
      - python3-openstackclient
      - python3-tornado

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

tornado_pip:
  pip.installed:
    - name: tornado
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

neutron_packages_salt-pip:
  pip.installed:
    -bin_env: '/use/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -openstackclient
      -tornado
    -require:
      -neutron_packages

  {% endif %}

{% elif grains['os_family'] == 'RedHat' %}

  {% if pillar['neutron']['backend'] == "linuxbridge" %}
neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron-ml2
      - openstack-neutron
      - python3-openstackclient

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

neutron_packages_salt-pip:
  pip.installed:
    -bin_env: '/use/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -python-openstackclient
    -require:
      -neutron_packages

  {% elif pillar['neutron']['backend'] == "openvswitch" %}
neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron-ml2
      - openstack-neutron
      - python3-openstackclient

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

neutron_packages_salt-pip:
  pip.installed:
    -bin_env: '/use/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -python-openstackclient
    -require:
      -neutron_packages

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

neutron_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron
      - openstack-neutron-ml2
      - python3-openstackclient
      - libibverbs
      - rdma-core

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

neutron_packages_salt-pip:
  pip.installed:
    -bin_env: '/use/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -python-openstackclient
    -require:
      -neutron_packages

  {% endif %}
{% endif %}
