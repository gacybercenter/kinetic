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

{% if grains['os_family'] == 'Debian' %}

repo-setup.sh:
  cmd.script:
    - name: repo-setup.sh
    - source: salt://formulas/common/rabbitmq/files/repo-setup.sh
    - unless:
      - cat /etc/apt/sources.list.d/rabbitmq.list | grep -q 'https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ jammy main'
      - cat /etc/apt/sources.list.d/rabbitmq.list | grep -q 'http://ppa.launchpad.net/rabbitmq/rabbitmq-erlang/ubuntu jammy main'

{% endif %}
