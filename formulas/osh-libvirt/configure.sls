include:
  - /formulas/osh-libvirt/install
  - /formulas/osh-helm-repos/configure
  - /formulas/neutron/configure

# Neutron must be up before Libvirt, not the other way around: Neutron's own
# chart has no dependency on Libvirt (verified against openstack-helm/neutron's
# values.yaml `dependencies` block - it only waits on oslo_db, oslo_messaging,
# oslo_cache, identity, and nova's compute/compute_metadata endpoints, plus its
# own neutron-ovs-agent on the same node). Libvirt's compute-node components
# need the neutron-ovs-agent DaemonSet already running (for OVS bridges, etc.),
# so Neutron is included above and required here. install_neutron won't return
# until its own `helm ... --wait` succeeds, which blocks until Neutron's pods
# are actually Ready (not just until Helm reports the release as deployed).
install_libvirt:
  k8s_helm.helm_release_present:
    - release_name: libvirt
    - chart_name: openstack-helm/libvirt
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - pillar_key: osh:libvirt:values
    - keep_values_file: false
    - require:
      - k8s_helm: install_neutron
