include:
  - /formulas/osh-rook-adapter/install
  - /formulas/osh-helm-repos/configure

install_ceph_adapter_rook:
  k8s_helm.helm_release_present:
    - release_name: ceph-adapter-rook
    - chart_name: openstack-helm/ceph-adapter-rook
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10