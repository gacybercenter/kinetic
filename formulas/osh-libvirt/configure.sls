include:
  - /formulas/osh-libvirt/install
  - /formulas/osh-helm-repos/configure

# Libvirt's compute-node components need Neutron's neutron-ovs-agent
# DaemonSet already running on the same nodes (for OVS bridges, etc.) before
# they can start - Neutron itself has no dependency on Libvirt. This formula
# intentionally does NOT include/require Neutron directly; that ordering is
# handled at the orchestration level instead (see
# orch/k8s-osh-compute-kit.sls), so each service's deployment is tracked as
# its own distinct orchestration step.
# wait: false - libvirt's DaemonSet pods on compute nodes won't report
# Ready until Neutron's neutron-ovs-agent DaemonSet is already running on
# those same nodes (see orch/k8s-osh-compute-kit.sls for the ordering).
# Blocking here on `helm ... --wait` would hang/timeout whenever Libvirt is
# deployed before Neutron already has Ready pods (e.g. first bootstrap).
install_libvirt:
  k8s_helm.helm_release_present:
    - release_name: libvirt
    - chart_name: openstack-helm/libvirt
    - namespace: openstack
    - wait: false
    - wait_timeout: 300
    - wait_interval: 10
    - pillar_key: osh:libvirt:values
    - keep_values_file: false
