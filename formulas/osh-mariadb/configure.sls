include:
  - /formulas/osh-mariadb/install
  - /formulas/osh-helm-repos/configure

install_mariadb:
  k8s_helm.helm_release_present:
    - release_name: mariadb
    - chart_name: openstack-helm/mariadb
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh_values:mariadb