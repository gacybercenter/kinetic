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
#{% for phases in pillar['hwmap'] %}
parallel_provision:
  salt.parallel_runners:
    - runners:
#  {% for type in pillar['hwmap'][phases] %}
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
                type: controllerv1
#  {% endfor %}
#{% endfor %}

## Bootstrap virtual hosts

##provision_virtual:
##  salt.runner:
##    - name: state.orchestrate
##    - mods: orch/virtual
##    - require:
##      - provision_controller
