include:
  - /formulas/rabbitmq/install

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
rmq_name_resolution_{{ server }}:
  host.present:
    - ip: {{ address[0] }}
    - names:
      - {{ server }}
    - clean: true
{% endfor %}

rabbitmq_unit_file_update:
  file.line:
    - name: /usr/lib/systemd/system/rabbitmq-server.service
    - content: After=network-online.target epmd@0.0.0.0.socket
    - match: After=network.target epmd@0.0.0.0.socket
    - mode: replace

systemctl daemon-reload:
  cmd.run:
    - onchanges:
      - file: rabbitmq_unit_file_update

/var/lib/rabbitmq/.erlang.cookie:
  file.managed:
    - contents_pillar: rabbitmq:erlang_cookie
    - mode: 400
    - user: rabbitmq
    - group: rabbitmq

rabbitmq-server-service:
  service.running:
    - name: rabbitmq-server
    - enable: true
    - watch:
      - /var/lib/rabbitmq/.erlang.cookie
    - require:
      - /var/lib/rabbitmq/.erlang.cookie

{% if grains['spawning'] != 0 %}
join_cluster:
  rabbitmq_cluster.join:
    - user: rabbit
  {% for server, address in salt['mine.get']('G@type:rabbitmq and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() %}
    - host: {{ server }}
  {% endfor %}
    - retry:
        attempts: 3
        until: True
        interval: 10
{% endif %}

cluster_policy:
  rabbitmq_policy.present:
    - name: ha
    - pattern: '^(?!amq\.).*'
    - definition: '{"ha-mode": "all"}'
    - require:
      - service: rabbitmq-server-service

### ref: https://github.com/saltstack/salt/issues/56258
### will need to use cmd.run for this until the above is merged
### in sodium
###openstack_rmq:
###  rabbitmq_user.present:
###    - password: {{ pillar['rabbitmq']['rabbitmq_password'] }}
###    - name: openstack
###    - perms:
###      - '/':
###        - '.*'
###        - '.*'
###        - '.*'
###    - require:
###      - service: rabbitmq-server-service

### legacy functions.  Remove this when the above works again
rabbitmqctl add_user openstack {{ pillar['rabbitmq']['rabbitmq_password'] }}:
  cmd.run:
    - unless:
      - rabbitmqctl list_users | grep -q openstack
    - require:
      - service: rabbitmq-server-service

rabbitmqctl set_permissions openstack ".*" ".*" ".*":
  cmd.run:
    - unless:
      - rabbitmqctl list_user_permissions openstack | grep -q '/'
    - require:
      - service: rabbitmq-server-service
### /legacy functions
