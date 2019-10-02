include:
  - /formulas/rabbitmq/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/rabbitmq/rabbit.conf:
  file.managed:
    - source: salt://formulas/rabbitmq/files/rabbitmq.conf

/etc/rabbitmq/rabbit-env.conf:
  file.managed:
    - source: salt://formulas/rabbitmq/files/rabbitmq-env.conf

rabbitmqctl hipe_compile /tmp/rabbit-hipe/ebin:
  cmd.run:
    - creates: /tmp/rabbit-hipe/ebin

rabbitmqctl add_user openstack {{ pillar['rabbitmq']['rabbitmq_password'] }}:
  cmd.run:
    - unless:
      - rabbitmqctl list_users | grep -q openstack

rabbitmqctl set_permissions openstack ".*" ".*" ".*":
  cmd.run:
    - onlyif:
      - rabbitmqctl add_user openstack

rabbitmq-server-service:
  service.running:
    - name: rabbitmq-server
    - watch:
      - /etc/rabbitmq/rabbit.conf
      - /etc/rabbitmq/rabbit-env.conf
      - rabbitmqctl hipe_compile /tmp/rabbit-hipe/ebin
