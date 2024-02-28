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

rabbitmq_erlang_repo:
  pkgrepo.managed:
    - humanname: RabbitMQ Erlang
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "http://ppa.launchpad.net/rabbitmq/rabbitmq-erlang/ubuntu/" + pillar['ubuntu']['name'] %}
    - name: deb [signed-by=/etc/apt/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
    {% endif %}
  {% endfor %}
{% else %}
    - name: deb [signed-by=/etc/apt/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg] http://ppa.launchpad.net/rabbitmq/rabbitmq-erlang/ubuntu {{ pillar['ubuntu']['name'] }} main
{% endif %}
    - file: /etc/apt/sources.list.d/rabbit-erlang.list
    - key_url: salt://formulas/common/rabbitmq/files/net.launchpad.ppa.rabbitmq.erlang.gpg
    - aptkey: False

rabbitmq_erlang_src_repo:
  pkgrepo.managed:
    - humanname: RabbitMQ Erlang - Source
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "http://ppa.launchpad.net/rabbitmq/rabbitmq-erlang/ubuntu/" + pillar['ubuntu']['name'] %}
    - name: deb-src [signed-by=/etc/apt/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
    {% endif %}
  {% endfor %}
{% else %}
    - name: deb-src [signed-by=/etc/apt/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg] http://ppa.launchpad.net/rabbitmq/rabbitmq-erlang/ubuntu {{ pillar['ubuntu']['name'] }} main
{% endif %}
    - file: /etc/apt/sources.list.d/rabbit-erlang-src.list
    - key_url: salt://formulas/common/rabbitmq/files/net.launchpad.ppa.rabbitmq.erlang.gpg
    - aptkey: False

rabbitmq_server_repo:
  pkgrepo.managed:
    - humanname: RabbitMQ Server
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/" + pillar['ubuntu']['name'] %}
    - name: deb [signed-by=/etc/apt/keyrings/io.packagecloud.rabbitmq.gpg arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
    {% endif %}
  {% endfor %}
{% else %}
    - name: deb [signed-by=/etc/apt/keyrings/io.packagecloud.rabbitmq.gpg] https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ {{ pillar['ubuntu']['name'] }} main
{% endif %}
    - file: /etc/apt/sources.list.d/rabbit-server.list
    - key_url: salt://formulas/common/rabbitmq/files/io.packagecloud.rabbitmq.gpg
    - aptkey: False

rabbitmq_server_src_repo:
  pkgrepo.managed:
    - humanname: RabbitMQ Server
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/" + pillar['ubuntu']['name'] %}
    - name: deb-src [signed-by=/etc/apt/keyrings/io.packagecloud.rabbitmq.gpg arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
    {% endif %}
  {% endfor %}
{% else %}
    - name: deb-src [signed-by=/etc/apt/keyrings/io.packagecloud.rabbitmq.gpg] https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ {{ pillar['ubuntu']['name'] }} main
{% endif %}
    - file: /etc/apt/sources.list.d/rabbit-server-src.list
    - key_url: salt://formulas/common/rabbitmq/files/io.packagecloud.rabbitmq.gpg
    - aptkey: False

update_packages_rabbitmq:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: rabbitmq_erlang_repo
      - pkgrepo: rabbitmq_erlang_src_repo
      - pkgrepo: rabbitmq_server_repo
      - pkgrepo: rabbitmq_server_src_repo
    - dist_upgrade: True
