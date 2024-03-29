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
  - /formulas/common/fluentd/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

opensearch_pull:
  cmd.run:
    - name: "salt-call --local dockercompose.pull /opt/opensearch/docker-compose.yml"
    - unless:
      - docker image ls | grep -q 'opensearchproject/opensearch'
      - docker image ls | grep -q 'opensearchproject/opensearch-dashboards'

opensearch_start:
  cmd.run:
    - name: "salt-call --local dockercompose.up /opt/opensearch/docker-compose.yml"
    - require:
      - opensearch_pull
    - unless:
      - docker exec -it opensearch-node1 whoami | grep -q opensearch

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}