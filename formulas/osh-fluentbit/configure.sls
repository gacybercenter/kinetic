include:
  - /formulas/osh-fluentbit/install
log_buffer_pvc:
  k8s.pvc_present:
    - name: log-buffer
    - namespace: openstack
    - storage_class: ceph-block
    - size: 1Gi

install_fluentbit:
  k8s_helm.helm_release_present:
    - release_name: fluentbit
    - chart_name: openstack-helm/fluentbit
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: True
    - pillar_key: osh_values:fluentbit
    - require:
      - k8s: log_buffer_pvc
