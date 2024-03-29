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
#  - /formulas/common/ceph/repo
#  - /formulas/common/frr/repo

{% if grains['os_family'] == 'Debian' %}
compute_packages:
  pkg.installed:
    - pkgs:
      - nova-compute
      - python3-tornado
      - ceph-common
      - spice-html5
      - python3-rbd
      - python3-rados
      - python3-etcd3gw
      - qemu-system-x86
      - nvme-cli
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
      - neutron-linuxbridge-agent
  {% elif pillar['neutron']['backend'] == "openvswitch" %}
      - neutron-openvswitch-agent
  {% elif pillar['neutron']['backend'] == "networking-ovn" %}
      - ovn-host
      - neutron-ovn-metadata-agent
      - haproxy
  {% endif %}
#      - frr
#      - frr-pythontools

compute_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - tornado
      - etcd3gw

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: True
    - pkgs:
      - tornado
      - etcd3gw
    - require:
      - pip: compute_pip

{% elif grains['os_family'] == 'RedHat' %}
compute_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-compute
      - python3-tornadonova-compute
      - python3-tornado
      - ceph-common
      - spice-html5
      - python3-etcd3gw
      - qemu-system
      - nvme-cli
      - ceph-common
      - python3-rbd
      - python3-rados
      - conntrack-tools
      - qemu-system-arm
      - qemu-system-mips
      - nvme-cli
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
      - openstack-neutron-linuxbridge
  {% elif pillar['neutron']['backend'] == "openvswitch" %}
      - openstack-openvswitch-agent
   {% elif pillar['neutron']['backend'] == "networking-ovn" %}
      - rdo-ovn-host
      - openstack-neutron-ovn-metadata-agent
      - openstack-neutron-common
      - haproxy
  {% endif %}
#      - frr
#      - frr-pythontools

compute_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - tornado
      - etcd3gw

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: True
    - pkgs:
      - tornado
      - etcd3gw
    - require:
      - pip: compute_pip

{% endif %}
