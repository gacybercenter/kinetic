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

{% macro spawnzero_complete() %}
spawnzero_complete:
  grains.present:
    - value: True
  module.run:
    - mine.send:
      - name: spawnzero_complete
      - args:
        - spawnzero_complete
      - kwargs:
          mine_function: grains.item
    - onchanges:
      - grains: spawnzero_complete

spawnzero_update:
  module.run:
    - mine.update:
    - require:
      - spawnzero_complete
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure
{% endmacro %}

{% macro check_spawnzero_status(type) %}
check_spawnzero_status:
  spawnzero.check:
    - name: check_spawnzero_status
    - type: {{ type }}
    - value: True
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endmacro %}
