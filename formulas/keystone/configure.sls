include:
  - /formulas/keystone/install
  - /formulas/osh-helm-repos/configure

install_keystone:
  k8s_helm.helm_release_present:
    - release_name: keystone
    - chart_name: openstack-helm/keystone
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh_values:keystone
    - set_values:
      - endpoints.oslo_db.auth.admin.username=root
      - endpoints.oslo_db.auth.admin.password={{ pillar['osh_values']['mariadb_admin'] }}
      - endpoints.oslo_db.auth.keystone.username=keystone
      - endpoints.oslo_db.auth.keystone.password={{ pillar['osh_values']['keystone_admin'] }}
      - endpoints.oslo_messaging.auth.admin.username=rabbitmq
      - endpoints.oslo_messaging.auth.admin.password={{ pillar['osh_values']['rabbitmq_admin'] }}
      - endpoints.oslo_messaging.auth.keystone.username=keystone
      - endpoints.oslo_messaging.auth.keystone.password={{ pillar['osh_values']['keystone-rq-user'] }}
      - identity.auth.admin.password={{ pillar['osh_users']['admin'] }}
      - identity.auth.test.password={{ pillar['osh_users']['test'] }}
