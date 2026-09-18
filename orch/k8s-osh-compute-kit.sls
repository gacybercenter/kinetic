# Orchestration script for the OpenStack "compute kit" - the set of
# OpenStack Helm services that make up compute-node functionality, deployed
# in dependency order with each service tracked as its own orchestration
# step.
#
# This intentionally does NOT rely on cross-formula `include`/`require`
# coupling inside the formulas themselves (e.g. formulas/osh-libvirt does
# not include formulas/neutron). Keeping the dependency graph here instead
# gives:
#   - a single place to see/extend the compute kit's service dependency
#     order, instead of it being implicit/hidden inside individual formulas
#   - per-service tracking in this orchestration job's return data - each
#     service is its own top-level step, not merged into another formula's
#     low state
#
# To add a new service to this kit: add another salt.state step below and
# wire its `require` to whatever it depends on.
#
# This script uses the k8s pillar value to target the minion where the
# installation should occur.

{% set k8s = salt['pillar.get']('k8s') %}

deploy_osh_openvswitch:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-openvswitch

deploy_osh_libvirt:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.osh-libvirt
    - require:
      - salt: deploy_osh_openvswitch

deploy_osh_placement:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.placement

deploy_osh_nova:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.nova
    - require:
      - salt: deploy_osh_placement

deploy_osh_neutron:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.neutron
    - require:
      - salt: deploy_osh_nova
