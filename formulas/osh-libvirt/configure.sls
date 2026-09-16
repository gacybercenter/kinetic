include:
  - /formulas/osh-libvirt/install
  - /formulas/osh-helm-repos/configure

install_libvirt:
  k8s_helm.helm_release_present:
    - release_name: libvirt
    - chart_name: openstack-helm/libvirt
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - pillar_key: osh:libvirt:values
    - keep_values_file: false
