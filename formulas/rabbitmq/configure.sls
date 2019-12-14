include:
  - formulas/rabbitmq/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
rmq_name_resolution_{{ server }}:
  host.present:
    - name: {{ address[0] }}
    - hostnames:
      - {{ server }}
{% endfor %}

/var/lib/rabbitmq/.erlang.cookie:
  file.managed:
    - contents_pillar: rabbitmq:erlang_cookie
    - mode: 400
    - user: rabbitmq
    - group: rabbitmq

/etc/rabbitmq/rabbit.conf:
  file.managed:
    - source: salt://formulas/rabbitmq/files/rabbitmq.conf

/etc/rabbitmq/rabbit-env.conf:
  file.managed:
    - source: salt://formulas/rabbitmq/files/rabbitmq-env.conf

rabbitmqctl hipe_compile /tmp/rabbit-hipe/ebin:
  cmd.run:
    - creates: /tmp/rabbit-hipe/ebin

openstack_rmq:
  rabbitmq_user.present:
    - password: {{ pillar['rabbitmq']['rabbitmq_password'] }}
    - name: openstack
    - perms:
      - '/':
        - '.*'
        - '.*'
        - '.*'
    - require:
      - service: rabbitmq-server-service

{% if grains['spawning'] != 0 %}
join_cluster:
  rabbitmq_cluster.join:
    - user: rabbit
  {% for server, address in salt['mine.get']('G@type:rabbitmq and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() %}
    - host: {{ server }}
  {% endfor %}
{% endif %}

rabbitmq-server-service:
  service.running:
    - name: rabbitmq-server
    - enable: true
    - watch:
      - /etc/rabbitmq/rabbit.conf
      - /etc/rabbitmq/rabbit-env.conf
      - rabbitmqctl hipe_compile /tmp/rabbit-hipe/ebin
      - /var/lib/rabbitmq/.erlang.cookie

cluster_policy:
  rabbitmq_policy.present:
    - name: ha
    - pattern: '^(?!amq\.).*'
    - definition: '{"ha-mode": "all"}'
    - require:
      - service: rabbitmq-server-service
