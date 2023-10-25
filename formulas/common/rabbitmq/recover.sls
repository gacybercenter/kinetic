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

{% set targets = {} %}
{% for id, value in salt['grains.equals']('role', 'rabbitmq') %}
  {% if value == True %}
    {% set targets = targets|set_dict_key_value('id', { grains['host'] }) %}
    {% set targets = targets|set_dict_key_value('spawning', { grains['spawning'] }) %}
  {% endif %}
{% endfor %}

rabbitmq_online:
  salt.function:
    - name: test.ping
    - tgt:
{% for id in targets|sort(attribute='spawning') %}
      - {{ id }}
{% endfor %}

rabbitmq_logrotate:
  salt.function:
    - name: cmd.run
    - tgt:
{% for id in targets|sort(attribute='spawning') %}
      - {{ id }}
{% endfor %}
    - arg:
      - /usr/sbin/logrotate /etc/logrotate.d/rabbitmq-server --force
    - require:
      - salt: rabbitmq_online

stop_rabbitmq_service:
  salt.function:
    - name: service.stop
    - tgt:
{% for id in targets|sort(attribute='spawning') %}
      - {{ id }}
{% endfor %}
    - arg:
      - rabbitmq-server
    - require:
      - salt: rabbitmq_online
      - salt: rabbitmq_logrotate

start_rabbitmq_service:
  salt.function:
    - name: service.start
    - tgt:
{% for id in targets|sort(attribute='spawning') %}
      - {{ id }}
{% endfor %}
    - arg:
      - rabbitmq-server
    - require:
      - salt: rabbitmq_online
      - salt: rabbitmq_logrotate
      - salt: stop_rabbitmq_service