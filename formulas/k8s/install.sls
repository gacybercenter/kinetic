## Copyright 2020 Augusta University
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

k8s_ipv4_forward:
  file.managed:
    - name: /etc/sysctl.d/k8s.configuration
    - contents: |
        net.ipv4.ip_forward = 1
k8s_ipv4_forward_commit:
  cmd.run:
    - name: sysctl --system
    - onchanges:
      - file: k8s_ipv4_forward

k8s_depends:
  pkg.installed:
    - pkgs:
      - ca-certificates
      - curl

k8s_packages:
  pkg.installed:
    - pkgs:
      - docker-ce
      - docker-ce-cli
      - containerd.io