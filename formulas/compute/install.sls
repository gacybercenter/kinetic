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
  - /formulas/common/ceph/repo
  - /formulas/common/frr/repo

{% if grains['os_family'] == 'Debian' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - nova-compute
      - neutron-linuxbridge-agent
      - python3-tornado
      - ceph-common
      - spice-html5
      - python3-rbd
      - python3-rados
      - frr
      - frr-pythontools

  {% elif pillar['neutron']['backend'] == "openvswitch" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - nova-compute
      - neutron-openvswitch-agent
      - python3-tornado
      - ceph-common
      - spice-html5
      - python3-rbd
      - python3-rados
      - frr
      - frr-pythontools

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

compute_packages:
  pkg.installed:
    - pkgs:
      - nova-compute
      - python3-tornado
      - ceph-common
      - spice-html5
      - python3-rbd
      - python3-rados
      - ovn-host
      - neutron-ovn-metadata-agent
      - haproxy
      - frr
      - frr-pythontools

  {% endif %}

{% elif grains['os_family'] == 'RedHat' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-compute
      - openstack-neutron-linuxbridge
      - python3-tornado
      - ceph-common
      - python3-rbd
      - python3-rados
      - conntrack-tools
      - frr
      - frr-pythontools

  {% elif pillar['neutron']['backend'] == "openvswitch" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-compute
      - openstack-openvswitch-agent
      - python3-tornado
      - ceph-common
      - python3-rbd
      - python3-rados
      - openstack-neutron-common
      - frr
      - frr-pythontools

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}
compute_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-compute
      - rdo-ovn-host
      - openstack-neutron-ovn-metadata-agent
      - python3-tornado
      - ceph-common
      - python3-rbd
      - python3-rados
      - openstack-neutron-common
      - haproxy
      - frr
      - frr-pythontools

  {% endif %}

{% endif %}
