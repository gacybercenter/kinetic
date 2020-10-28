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

/etc/guacamole/guacamole.properties:
  file.managed:
    - contents: |
        guacd-hostname: localhost
        guacd-port:     4822

/etc/guacamole/user-mapping.xml:
  file.managed:
    - contents: |
        <user-mapping>
          <authorize username="foo" password="bar">
          </authorize>
        </user-mapping>

guacd_service:
  service.running:
    - enable: True
    - name: guacd
    - watch:
      - file: /etc/guacamole/guacamole.properties

tomcat_service:
  service.running:
    - enable: True
    - name: tomcat9
    - watch:
      - file: /etc/guacamole/guacamole.properties
