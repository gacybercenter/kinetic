include:
  - /formulas/osh-fluentd/install

install_fluentd:
  k8s_helm.helm_release_present:
    - release_name: fluentd
    - chart_name: openstack-helm/fluentd
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: True
    - pillar_key: osh_values:fluentd
    - set_values:
      - endpoints.elasticsearch.auth.admin.password={{ pillar['opensearch_fluentbit_password'] }}
