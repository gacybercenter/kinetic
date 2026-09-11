include:
  - /formulas/osh-rabbitmq/install
  - /formulas/osh-helm-repos/configure

install_rabbitmq:
  k8s_helm.helm_release_present:
    - release_name: rabbitmq
    - chart_name: openstack-helm/rabbitmq
    - namespace: openstack
    - wait_timeout: 600
    - wait_interval: 10
    - keep_values_file: false
    - pillar_key: osh:rabbitmq
    - set_values:
      - endpoints.oslo_messaging.auth.user.username=rabbitmq
      - endpoints.oslo_messaging.auth.user.password={{ pillar['osh']['rabbitmq_admin'] }}
