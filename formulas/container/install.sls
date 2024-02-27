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
 #  - /formulas/common/ceph/repo
  - /formulas/common/docker/repo
  - /formulas/common/kata/repo

{% if pillar['neutron']['backend'] == "linuxbridge" %}
container_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - docker-ce
      - neutron-linuxbridge-agent
      - python3-tornado
      - python3-pymysql
      - kata-runtime
      - kata-proxy
      - kata-shim
      - python3-etcd3gw
      - open-iscsi
      - ceph-common

container.pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - pymysql
      - python-openstackclient
      - tornado
      - etcd3gw

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - pymysql
      - python-openstackclient
      - etcd3gw
      - tornado
    - require:
      - pip: container_pip

{% elif pillar['neutron']['backend'] == "openvswitch" %}
container_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - docker-ce
      - neutron-openvswitch-agent
      - python3-tornado
      - python3-pymysql
      - kata-runtime
      - kata-proxy
      - kata-shim
      - numactl
      - python3-etcd3gw
      - open-iscsi
      - ceph-common

container.pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - pymysql
      - python-openstackclient
      - tornado
      - etcd3gw

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - pymysql
      - python-openstackclient
      - etcd3gw
      - tornado
    - require:
      - pip: container_pip

{% elif pillar['neutron']['backend'] == "networking-ovn" %}

container_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - docker-ce
      - ovn-host
      - python3-tornado
      - python3-pymysql
      - kata-runtime
      - kata-proxy
      - kata-shim
      - python3-etcd3gw
      - open-iscsi
      - ceph-common

container.pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - pymysql
      - python-openstackclient
      - tornado
      - etcd3gw

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - pymysql
      - python-openstackclient
      - etcd3gw
      - tornado
    - require:
      - pip: container_pip

{% endif %}

pymysql_sa:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

kuryr:
  group.present:
    - system: True
  user.present:
    - shell: /bin/false
    - createhome: True
    - home: /var/lib/kuryr
    - system: True
    - groups:
      - kuryr

/etc/kuryr:
  file.directory:
    - user: kuryr
    - group: kuryr
    - mode: "0755"
    - makedirs: True

{% for user in ['zun', 'kuryr'] %}
{{ user }}_config:
  cmd.run:
    - name: git config --system --add safe.directory "/var/lib/{{ user }}"
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure
{% endfor %}

kuryr_latest:
  git.latest:
    - name: https://git.openstack.org/openstack/kuryr-libnetwork.git
    - branch: stable/antelope
    - target: /var/lib/kuryr
    - force_clone: true
    - require:
      - cmd: kuryr_config

kuryr_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/kuryr/requirements.txt
    - unless:
      - systemctl is-active kuryr-libnetwork
    - require:
      - git: kuryr_latest

installkuryr:
  cmd.run:
    - name: python3 setup.py install
    - cwd: /var/lib/kuryr/
    - unless:
      - systemctl is-active kuryr-libnetwork
    - require:
      - cmd: kuryr_requirements

zun:
  group.present:
    - system: True
  user.present:
    - shell: /bin/false
    - createhome: True
    - home: /var/lib/zun
    - system: True
    - groups:
      - zun

/etc/zun:
  file.directory:
    - user: zun
    - group: zun
    - mode: "0755"
    - makedirs: True

/etc/zun/rootwrap.d:
  file.directory:
    - user: root
    - group: root
    - makedirs: True

zun_latest:
  git.latest:
    - name: https://git.openstack.org/openstack/zun.git
    - branch: stable/antelope
    - target: /var/lib/zun
    - force_clone: true
    - require:
      - cmd: zun_config

zun_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/zun/requirements.txt
    - unless:
      - systemctl is-active zun-compute
    - require:
      - git: zun_latest

installzun:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/zun/
    - unless:
      - systemctl is-active zun-compute
    - require:
      - cmd: zun_requirements
