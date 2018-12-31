include:
  - /formulas/rabbitmq/install
  - formulas/common/base
  - formulas/common/networking

rabbitmqctl add_user openstack {{ pillar['rabbitmq']['rabbitmq_password'] }}:
  cmd.run:
    - unless:
      - rabbitmqctl list_users | grep -q openstack

rabbitmqctl set_permissions openstack ".*" ".*" ".*":
  cmd.run
