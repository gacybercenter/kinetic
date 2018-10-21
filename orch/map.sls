master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

pxe_setup:
  salt.state:
    - tgt: 'pxe'
    - highstate: true
    - require:
      - master_setup

## Bootstrap physical hosts
parallel_provision:
  salt.parallel_runners:
    - runners:
        provision_controller:
          - name: state.orchestrate
          - kwarg:
              mods: orch/bootstrap
              pillar:
                type: controller
        provision_controllerv2:
          - name: state.orchestrate
          - kwarg:
              mods: orch/bootstrap
              pillar:
                type: controllerv2

## Bootstrap virtual hosts

##provision_virtual:
##  salt.runner:
##    - name: state.orchestrate
##    - mods: orch/virtual
##    - require:
##      - provision_controller
