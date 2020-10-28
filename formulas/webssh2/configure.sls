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
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

webssh2:
  user.present:
    - shell: /bin/false

/var/www/html/app/config.json:
  file.managed:
    - source: salt://formulas/webssh2/files/config.json
    - template: jinja
    - defaults:
        allowed_subnets: {{ pillar['networking']['subnets']['public'] }}
        session_name: {{ pillar['webssh2']['session_name'] }}
        session_secret: {{ pillar['webssh2']['session_secret'] }}

/etc/systemd/system/webssh2.service:
  file.managed:
    - source: salt://formulas/webssh2/files/webssh2.service
    - mode: 644

webssh2_service:
  service.running:
    - enable: True
    - name: webssh2
    - watch:
      - file: /var/www/html/app/config.json
