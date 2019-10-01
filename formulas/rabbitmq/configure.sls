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

rabbitmqctl add_user openstack {{ pillar['rabbitmq']['rabbitmq_password'] }}:
  cmd.run:
    - unless:
      - rabbitmqctl list_users | grep -q openstack

rabbitmqctl set_permissions openstack ".*" ".*" ".*":
  cmd.run:
    - unless:
      - rabbitmqctl list_user_permissions openstack
