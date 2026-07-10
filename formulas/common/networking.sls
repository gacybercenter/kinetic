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

# Remove legacy networking tools
ifupdown:
  pkg.removed

netplan.io:
  pkg.installed

# Clean up legacy networking files
/etc/network/interfaces:
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

# Generate Netplan configuration
# Generate and apply Netplan configuration using the new kinetic_netplan module
ensure_netplan_config:
  kinetic_netplan.config_present:
    - apply_immediately: True

# === Promiscuous Mode Service (declarative) ===

# Build list of physical interfaces for non-management networks
{%- set host_type = grains['type'] %}
{%- set non_mgmt_interfaces = [] %}
{%- for network, config in pillar['hosts'][host_type]['networks'].items() if network != 'management' and config.get('managed', True) %}
  {%- for iface in config.get('interfaces', []) %}
    {%- do non_mgmt_interfaces.append(iface) %}
  {%- endfor %}
{%- endfor %}

# Install the systemd service (enables promisc on physical interfaces)
promisc-mode-service-file:
  file.managed:
    - name: /etc/systemd/system/promisc-mode.service
    - source: salt://formulas/common/networking/files/promisc-mode.service.j2
    - template: jinja
    - mode: 644
    - context:
        interfaces: {{ non_mgmt_interfaces | unique | list }}

# Enable and start the service
promisc-mode-service:
  service.running:
    - name: promisc-mode
    - enable: True
    - require:
      - file: promisc-mode-service-file
