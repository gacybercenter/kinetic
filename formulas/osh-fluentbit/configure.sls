include:
  - /formulas/osh-fluentbit/install

install_fluentbit:
  k8s_helm.helm_release_present:
    - release_name: fluentbit
    - chart_name: openstack-helm/fluentbit
    - namespace: openstack
    - wait_timeout: 600
    - wait_interval: 10
    - keep_values_file: True
    - pillar_key: osh_values:fluentbit
