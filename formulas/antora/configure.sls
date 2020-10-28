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

docs_source:
  git.latest:
    - name: {{ pillar ['antora']['repo_url'] }}
    - target: /root/src/

theme_source:
  file.managed:
    - name: /root/theme.zip
    - source: {{ pillar ['antora']['theme_url'] }}
    - source_hash: {{ pillar ['antora']['theme_hash_url'] }}

/root/site.yml:
  file.managed:
    - source: salt://formulas/antora/files/site.yml
    - template: jinja
    - defaults:
        antora_docs_repo: {{ pillar ['antora']['repo_url'] }}
        docs_domain: {{ pillar['haproxy']['docs_domain'] }}
        antora_theme_url: {{ pillar ['antora']['theme_url'] }}

wipe_cache:
  file.absent:
    - name: /root/.cache/antora
    - onchanges:
      - git: docs_source
      - file: /root/site.yml
      - file: theme_source

generate_site:
  cmd.run:
    - name: antora generate --fetch --clean /root/site.yml
    - require:
      - file: wipe_cache
    - onchanges:
      - git: docs_source
      - file: /root/site.yml
      - file: theme_source

apache2_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: httpd
{% endif %}
    - enable: true
