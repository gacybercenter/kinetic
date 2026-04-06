include:
  - /formulas/osh-memcached/install
  - /formulas/osh-helm-repos/configure

install_memcached:
  k8s_helm.helm_release_present:
    - release_name: memcached
    - chart_name: openstack-helm/memcached
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh_values:memcached