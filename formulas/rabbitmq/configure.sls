include:
  - /formulas/rabbitmq/install
  - /formulas/common/base
  - /formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

## workaround for hipe compilation
## warning: the VM is running with native name encoding of latin1 which may cause Elixir to malfunction as it expects utf8.
## Please ensure your locale is set to UTF-8 (which can be verified by running "locale" in your shell)

{% for server, address in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
rmq_name_resolution_{{ server }}:
  host.present:
    - ip: {{ address[0] }}
    - names:
      - {{ server }}
    - clean: true
{% endfor %}

/var/lib/rabbitmq/.erlang.cookie:
  file.managed:
    - contents_pillar: rabbitmq:erlang_cookie
    - mode: 400
    - user: rabbitmq
    - group: rabbitmq

#/etc/rabbitmq/rabbit.conf:
#  file.managed:
#    - source: salt://formulas/rabbitmq/files/rabbitmq.conf

#/etc/rabbitmq/rabbit-env.conf:
#  file.managed:
#    - source: salt://formulas/rabbitmq/files/rabbitmq-env.conf

### http://erlang.2086793.n4.nabble.com/HiPE-in-OTP-22-td4725613.html
### HIPE is no longer supported
###
###rabbitmqctl hipe_compile /tmp/rabbit-hipe/ebin:
###  cmd.run:
###    - creates: /tmp/rabbit-hipe/ebin


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

rabbitmqctl set_permissions openstack ".*" ".*" ".*":
  cmd.run:
    - unless:
      - rabbitmqctl list_user_permissions openstack

### /legacy functions

{% if grains['spawning'] != 0 %}
join_cluster:
  rabbitmq_cluster.join:
    - user: rabbit
  {% for server, address in salt['mine.get']('G@type:rabbitmq and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() %}
    - host: {{ server }}
  {% endfor %}
    - retry:
        attempts: 5
        until: True
        interval: 60
{% endif %}

rabbitmq-server-service:
  service.running:
    - name: rabbitmq-server
    - enable: true
    - watch:
#      - /etc/rabbitmq/rabbit.conf
#      - /etc/rabbitmq/rabbit-env.conf
###      - rabbitmqctl hipe_compile /tmp/rabbit-hipe/ebin
      - /var/lib/rabbitmq/.erlang.cookie

cluster_policy:
  rabbitmq_policy.present:
    - name: ha
    - pattern: '^(?!amq\.).*'
    - definition: '{"ha-mode": "all"}'
    - require:
      - service: rabbitmq-server-service
