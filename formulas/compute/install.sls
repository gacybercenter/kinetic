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
      - qemu-system-arm
      - qemu-system-ppc
      - qemu-system-s390x
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

## NOTE(chateaux): This is a temporary workaround for the arm64 compute nodes
##                 to compile libvirtd from source due to newer neoverse-n1
##                 processors not being supported by libvirt version 8.X
##
##                 Reference https://libvirt.org/compiling.html, and
##                 https://download.libvirt.org/
{% if grains['type'] == 'arm' %}
compile_libvirt_pkgs:
  pkg.installed:
    - pkgs:
      - meson
      - xsltproc
      - pkg-config
      - libglib2.0-dev
      - libgnutls28-dev
      - libxml2-dev
      - libyajl-dev
      - libudev-dev

/root/libvirtd-10-rc-patch.sh:
  file.managed:
    - mode: "0755"
    - source: salt://formulas/compute/files/libvirtd-10-rc-patch.sh

compile_libvirt:
  cmd.run:
    - name: /root/libvirtd-10-rc-patch.sh
    - cwd: /root
    - require:
      - pkg: compile_libvirt_pkgs
      - file: /root/libvirtd-10-rc-patch.sh
    - unless: libvirtd --version | grep '10.0'
{% endif %}

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
