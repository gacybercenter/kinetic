## Copyright 2019 Augusta University
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

{% if pillar['neutron']['backend'] == "linuxbridge" %}
network_packages:
  pkg.installed:
    - pkgs:
      - neutron-plugin-ml2
      - neutron-linuxbridge-agent
      - neutron-l3-agent
      - neutron-dhcp-agent
      - neutron-metadata-agent
      - python3-openstackclient
      - python3-tornado
      - python3-etcd3gw

network_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - tornado
      - etcd3gw

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
      - tornado
      - etcd3gw
    - require:
      - pip: network_packages

{% elif pillar['neutron']['backend'] == "openvswitch" %}

network_packages:
  pkg.installed:
    - pkgs:
      - neutron-plugin-ml2
      - neutron-openvswitch-agent
      - neutron-l3-agent
      - neutron-dhcp-agent
      - neutron-metadata-agent
      - python3-openstackclient
      - python3-tornado

network_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - tornado

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
      - tornado
    - require:
      - pip: network_pip

{% endif %}

## taas
git_config_safe_dir:
  git.config_set:
    - name: safe.directory
    - value: "/var/lib/taas"
    - global: True
git_config_email:
  git.config_set:
    - name: user.email
    - value: "gacyberrange@augusta.edu"
    - global: True
git_config_user:
  git.config_set:
    - name: user.name
    - value: "gacyberrange"
    - global: True

taas_latest:
  git.latest:
    - name: https://opendev.org/openstack/tap-as-a-service.git
    - branch: stable/2024.1
    - target: /var/lib/taas
    - force_clone: true
    - force_reset: true
    - rev: stable/2024.1
    - require:
      - git: git_config_safe_dir

taas_virtenv:
  virtualenv.managed:
    - name: /var/lib/taas
    - systems_site_packages: True
    - venv_bin: /var/lib/taas/bin
    - requirements: /var/lib/taas/requirements.txt
