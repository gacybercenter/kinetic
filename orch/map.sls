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
{% for phase in pillar['hwmap'] %}
parallel_provision_{{ phase }}:
  salt.parallel_runners:
    - runners:
  {% for type in pillar['hwmap'][phase] %}
  {% if type == 'cephmon' %}
        provision_{{ type }}:
          - name: state.orchestrate
          - kwarg:
              mods: orch/virtual
              pillar:
                type: {{ type }}
  {% else %}
        provision_{{ type }}:
          - name: state.orchestrate
          - kwarg:
              mods: orch/bootstrap
              pillar:
                type: {{ type }}
  {% endfor %}
{% endfor %}
## Bootstrap virtual hosts

##provision_virtual:
##  salt.runner:
##    - name: state.orchestrate
##    - mods: orch/virtual
##    - require:
##      - provision_controller
