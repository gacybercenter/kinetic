## Copyright 2021 United States Army Cyber School
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

salt-proxy@qfx5200-32c-r1-sw1-spine:
  service.running:
    - enable: True

salt-proxy@qfx5200-32c-r2-sw5-spine:
  service.running:
    - enable: True

salt-proxy@qfx5200-48y-r1-sw2-leaf:
  service.running:
    - enable: True

salt-proxy@qfx5200-48y-r1-sw3-leaf:
  service.running:
    - enable: True

salt-proxy@qfx5200-48y-r2-sw6-leaf:
  service.running:
    - enable: True

salt-proxy@qfx5200-48y-r2-sw7-leaf:
  service.running:
    - enable: True


salt-proxy@ex3400-48t-r1-sw4-oob-vc:
  service.running:
    - enable: True


salt-proxy@ex3400-48t-r2-sw9-wan:
  service.running:
    - enable: True


{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}