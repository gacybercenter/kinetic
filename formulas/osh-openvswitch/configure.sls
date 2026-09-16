include:
  - /formulas/osh-openvswitch/install
  - /formulas/osh-helm-repos/configure

install_openvswitch:
  k8s_helm.helm_release_present:
    - release_name: openvswitch
    - chart_name: openstack-helm/openvswitch
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - pillar_key: osh:openvswitch:values
    - keep_values_file: false
