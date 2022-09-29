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
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

python manage.py migrate:
  cmd.run:
    - require:
      - file: /etc/yuyu/yuyu.conf
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

python manage.py createsuperuser:

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

conf-files:
  file.managed:
    - makedirs: true
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
    - names:
      - /var/lib/yuyu/yuyu/local_settings.py:
        - source: salt://formulas/yuyu/files/yuyu.conf
      - /etc/systemd/system/yuyu_api.service:
        - source: salt://formulas/yuyu/files/yuyu_api.service
      - /etc/systemd/system/yuyu_event_monitor.service:
        - source: salt://formulas/yuyu/files/yuyu_event_monitor.service
    - require:
      - sls: /formulas/yuyu/install

/var/yuyu/bin/process_invoice.sh:
  cron.present:
    - user: root
    - 
yuyu_api_service:
  service.running:
    - name: yuyu_api
    - enable: true
    - watch:
      - file: /var/lib/yuyu/yuyu/local_settings.py

yuyu_wsproxy_service:
  service.running:
    - name: yuyu_event_monitor
    - enable: true
    - watch:
      - file: /var/lib/yuyu/yuyu/local_settings.py
