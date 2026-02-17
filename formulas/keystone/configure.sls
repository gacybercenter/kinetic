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
