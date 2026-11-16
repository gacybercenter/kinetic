# Orchestration script to deploy OpenStack Helm Libvirt.
# This script uses the k8s pillar value to target the minion where the installation should occur.
#
# NOTE: formulas.osh-libvirt now also includes formulas/neutron/configure
# (Libvirt's compute-node components need Neutron's neutron-ovs-agent
# DaemonSet already running on the same nodes), and install_libvirt
# requires install_neutron. Since there is no standalone k8s-osh-neutron.sls
# orchestration file, applying this orchestration deploys Neutron first (its
# own `helm ... --wait` blocks until its pods are actually Ready), then
# Libvirt, in a single salt.state run on the same target - no separate
# Neutron orchestration step is needed.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_libvirt:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-libvirt
