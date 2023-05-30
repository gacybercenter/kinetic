## Copyright 2021 United States Army Cyber School
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
  - /formulas/compute/install

## Update hash if any upgrades to cuda keyring
gpu-keyring:
  file.managed:
    - name: /root/cuda-keyring_1.0-1_all.deb
    - source: https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
    - source_hash: 0c4a40cc2caa6a847acbe6d4825a7cf625b7044776243101c0f1164c17b925b3
    - mode: "0755"

## Only run the installer if the nvidia-installer-disable-nouveau.conf file is not found
## this should only allow the installer to run initially
install-keyring:
  cmd.run:
    - name: ./cuda-keyring_1.0-1_all.deb
    - cwd: /root
    - creates:
      - /usr/lib/modprobe.d/nvidia-installer-disable-nouveau.conf
    - require:
      - file: gpu-keyring

{% if pillar['gpu']['backend'] == "cyborg" %}
cyborg_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - python3-memcache
      - python3-pymysql
      - dkms
      - python3-etcd3gw
      - xorg-dev
      - libvulkan1
      - cuda
    - require:
      - cmd: install-keyring

python3-openssl:
  pkg.installed:
    - version: 19.0.0-1build1

pymysql_sa:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

eventlet:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

python-cyborgclient:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

cyborg:
  group.present:
    - system: True
  user.present:
    - shell: /bin/false
    - createhome: True
    - home: /var/lib/cyborg
    - system: True
    - groups:
      - cyborg

/etc/cyborg:
  file.directory:
    - user: cyborg
    - group: cyborg
    - mode: "0755"
    - makedirs: True

/var/log/cyborg:
  file.directory:
    - user: cyborg
    - group: adm
    - mode: "0755"
    - makedirs: True

git_config:
  cmd.run:
    - name: git config --system --add safe.directory "/var/lib/cyborg"
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

cyborg_latest:
  git.latest:
    - name: https://opendev.org/openstack/cyborg.git
    - branch: stable/2023.1
    - target: /var/lib/cyborg
    - force_clone: True
    - force_reset: True
    - require:
      - cmd: git_config

cyborg_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/cyborg/requirements.txt
    - unless:
      - systemctl is-active cyborg-agent
    - require:
      - git: cyborg_latest

install_cyborg:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/cyborg/
    - unless:
      - systemctl is-active cyborg-agent
    - require:
      - cmd: cyborg_requirements

{% endif %}

