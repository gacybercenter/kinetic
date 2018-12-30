include:
  - /formulas/rabbitmq/install
  - formulas/common/base
  - formulas/common/networking

mine.update:
  module.run

rabbitmqctl add_user openstack {{ pillar['rabbitmq_password'] }}:
  cmd.run:
    - unless:
      - rabbitmqctl list_users | grep -q openstack

rabbitmqctl set_permissions openstack ".*" ".*" ".*":
  cmd.run
