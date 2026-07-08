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
  - /formulas/common/nftables/nftables

network_util:
  pkg.installed:
    - name: ifupdown
# netplan.io:
#   pkg.removed

/etc/netplan:
  file.absent

/run/systemd/network:
  file.absent
systemd-networkd.socket:
  service.disabled
systemd-networkd:
  service.disabled
NetworkManager:
  service.disabled

pin_salt_pip_version:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - names:
      - pip=={{ pillar['pip']['version'] }}

pyroute2_salt_pip:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: True
    - pkgs:
      - pyroute2
      - pyroute2.ndb
      - pyroute2.ipdb
    - require:
      - pin_salt_pip_version

## Patch pyroute2 to fix a bug in the compat module until it is fixed upstream
## https://github.com/svinota/pyroute2/issues/1132
## https://github.com/svinota/pyroute2/pull/1133
## https://github.com/saltstack/salt/issues/65361
# pyroute2_patch:
#   file.managed:
#     - makedirs: True
#     - names:
#       - /opt/saltstack/salt/extras-3.10/pyroute2/ndb/compat.py:
#         - source: salt://formulas/common/pyroute2/compat.py
#       - /usr/local/lib/python3.10/dist-packages/pyroute2/ndb/compat.py:
#         - source: salt://formulas/common/pyroute2/compat.py
#     - require:
#       - pip: pyroute2_salt_pip
# ###

## This state doesn't apply to salt/pxe past this point

## disable unneeded services and enable needed ones
##


### The stub resolver is causing bizarre issues and
### intermittently returning publicly routable addresses
### for hosts statically defined on the DNS server
### This symlink points at the full resolver
### You should only do this with versions of systemd
### 241 or greater

# /etc/resolv.conf:
#   file.symlink:
#     - target: /run/systemd/resolve/resolv.conf
#     - force: True

/etc/network/interfaces:
  file.managed:
    - source: salt://formulas/common/networking/files/interfaces.j2
    - template: jinja
    - mode: 644
    - user: root
    - group: root

# Restart networking when the interfaces file changes
networking-restart:
  service.running:
    - name: networking
    - watch:
      - file: /etc/network/interfaces
