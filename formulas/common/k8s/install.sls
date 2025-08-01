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
# Setup the Kubernetes repo
Install Salt Kubernetes extension:
  pip.installed:
    - bin_env: /opt/saltstack/salt/bin
    - name: saltext-kubernetes
kube.repo:
  pkgrepo.managed:
    - name: {{ pillar['k8s_repo'] }}
    - file: {{ pillar['k8s_source_file'] }}
    - key_url: {{ pillar['k8s_gpg_key'] }}
crio_repo:
  pkgrepo.managed:
    - name: {{ pillar['crio_repo'] }}
    - file: {{ pillar['crio_source_file'] }}
    - key_url: {{ pillar['crio_gpg_key'] }}

# Install Kubernetes
kube.packages:
  pkg.installed:
    - hold: True
    - pkgs:
      - kubelet
      - kubeadm
      - kubectl
      - ca-certificates
      - curl
      - apt-transport-https
      - gpg
      - make
      - cri-o