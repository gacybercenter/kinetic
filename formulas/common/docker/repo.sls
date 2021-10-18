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

{% if grains['os_family'] == 'Debian' %}

docker_repo:
  pkgrepo.managed:
    - humanname: docker
    - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable
    - file: /etc/apt/sources.list.d/docker.list
    - key_url: https://download.docker.com/linux/ubuntu/gpg

update_packages_docker:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - docker_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

docker_repo:
  pkgrepo.managed:
    - name: docker
    - baseurl: https://download.docker.com/linux/centos/8/$basearch/stable
    - file: /etc/yum.repos.d/docker.repo
    - gpgkey: https://download.docker.com/linux/centos/gpg

update_packages_docker:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - docker_repo

{% endif %}
