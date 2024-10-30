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

cache_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - docker.io
      - docker-compose
      - containerd
    - reload_modules: True

## Install docker pip module version 5.0.3 due to bug in 6.0.0, as seen here related to saltstack
## https://github.com/saltstack/salt/issues/62602
cache_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - pkgs:
      - docker == 5.0.3
    - reload_modules: true
    - require:
      - pkg: cache_packages


salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - pkgs:
      - docker == 5.0.3
    - reload_modules: true
    - require:
      - pkg: cache_packages
      - pip: cache_pip

/etc/nexus/admin.password:
  file.managed:
    - makedirs: True
    - replace: False
    - contents: placeholder

nexusproxy:
  docker_container.running:
    - name: nexusproxy
    - image: sonatype/nexus3:latest
    - restart_policy: unless-stopped
    - ports:
      - 8081
      - 8082
      - 8083
      - 8084
    - port_bindings:
      - {{ pillar['cache']['nexusproxy']['port'] }}:8081
      - {{ pillar['cache']['nexusproxy']['docker'] }}:8082
      - {{ pillar['cache']['nexusproxy']['quay'] }}:8083
      - {{ pillar['cache']['nexusproxy']['gitlab'] }}:8084

nexusproxy_online:
  cmd.run:
    - name: docker exec nexusproxy ls -al /nexus-data/ | grep -q 'admin.password'
    - retry:
        attempts: 60
        delay: 10
        splay: 5
    - require:
      - docker_container: nexusproxy
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

nexusproxy_connection:
  module.run:
    - network.connect:
      - host: {{ salt['network.ip_addrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
      - port: {{ pillar['cache']['nexusproxy']['port'] }}
    - retry:
        attempts: 30
        delay: 10
        splay: 5
    - require:
      - docker_container: nexusproxy
      - cmd: nexusproxy_online
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

admin_password:
  cmd.run:
    - name: salt-call grains.setval original_password $(docker exec nexusproxy cat /nexus-data/admin.password)
    - retry:
        attempts: 30
        delay: 10
        splay: 5
    - require:
      - docker_container: nexusproxy
      - cmd: nexusproxy_online
      - module: nexusproxy_connection
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure