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

yuyu:
  group.present:
    - system: True
  user.present:
    - shell: /bin/false
    - createhome: True
    - home: /var/lib/yuyu
    - system: True
    - groups:
      - yuyu

/etc/yuyu:
  file.directory:
    - user: yuyu
    - group: yuyu
    - mode: "0755"
    - makedirs: True

git_config:
  cmd.run:
    - name: git config --system --add safe.directory "/var/lib/yuyu"
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

yuyu_latest:
  git.latest:
    - name: https://github.com/btechpt/yuyu.git
    - branch: v1.0-alpha
    - target: /var/lib/yuyu
    - force_clone: true
    - require:
      - cmd: git_config

yuyu_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/yuyu/requirements.txt
    - unless:
      - systemctl is-active yuyu-api
    - require:
      - git: yuyu_latest
