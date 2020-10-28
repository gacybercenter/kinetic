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
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/logs/logs:
  file.directory:
    - user: elasticsearch
    - group: elasticsearch
    - makedirs: True

/logs/data:
  file.directory:
    - user: elasticsearch
    - group: elasticsearch
    - makedirs: True

/etc/elasticsearch/elasticsearch.yml:
  file.managed:
    - source: salt://formulas/graylog/files/elasticsearch.yml
    - template: jinja
    - defaults:
        graylog_cluster: graylog

/etc/graylog/server/server.conf:
  file.managed:
    - source: salt://formulas/graylog/files/server.conf
    - template: jinja
    - defaults:
        password_secret: {{ pillar['graylog']['graylog_password'] }}
        root_password_sha2: {{ pillar['graylog']['graylog_password_sha2'] }}
        http_bind_address: {{ grains['ipv4'][0] }}:9000
        root_timezone: {{ pillar['timezone'] }}

mongodb_service:
  service.running:
    - enable: True
    - name: mongod.service

elasticsearch_service:
  service.running:
    - name: elasticsearch
    - enable: True
    - watch:
      - /etc/elasticsearch/elasticsearch.yml
    - require:
      - file: /etc/elasticsearch/elasticsearch.yml
      - service: mongodb_service

graylog_service:
  service.running:
    - name: graylog-server
    - enable: True
    - watch:
      - /etc/graylog/server/server.conf
    - require:
      - file: /etc/graylog/server/server.conf
      - service: elasticsearch_service

rest_conf:
  cmd.script:
    - source: salt://formulas/graylog/files/restconf.sh
    - template: jinja
    - defaults:
        password_secret: {{ pillar['graylog']['graylog_password'] }}
        http_bind_address: {{ grains['ipv4'][0] }}
    - require:
      - service: graylog_service
