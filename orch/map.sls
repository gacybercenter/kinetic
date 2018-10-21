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
{% for phases in pillar['hwmap'] %}
parallel_provision_{{ phases }}:
  salt.parallel_runners:
    - runners:
  {% for type in pillar['hwmap'][phases] %}
        provision_{{ type }}:
          - name: state.orchestrate
          - kwarg:
              mods: orch/bootstrap
              pillar:
                type: {{ type }}
              concurrent: true
  {% endfor %}
{% endfor %}

## Bootstrap virtual hosts

##provision_virtual:
##  salt.runner:
##    - name: state.orchestrate
##    - mods: orch/virtual
##    - require:
##      - provision_controller
