include:
  - formulas/graylog/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}
spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."
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
        http_bind_address: http://{{ grains['ipv4'][0] }}:9000/
        rest_listen_uri: http://{{ grains['ipv4'][0] }}:9000/api/
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

graylog_service:
  service.running:
    - name: graylog-server
    - enable: True
    - watch:
      - /etc/graylog/server/server.conf
