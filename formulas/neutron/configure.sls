include:
  - /formulas/neutron/install
  - /formulas/osh-helm-repos/configure

install_neutron:
  k8s_helm.helm_release_present:
    - release_name: neutron
    - chart_name: openstack-helm/neutron
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - pillar_key: osh:neutron:values
    - keep_values_file: false
