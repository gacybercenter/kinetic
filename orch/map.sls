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

{% for phase in pillar['map'] %}
parallel_provision_{{ phase }}:
  salt.parallel_runners:
    - runners:
  {% for type in pillar['map'][phase] %}
        provision_{{ type }}:
          - name: state.orchestrate
          - kwarg:
              mods: orch/generate
              pillar:
                type: {{ type }}
  {% endfor %}
{% endfor %}


## Bootstrap physical hosts
# {% for phase in pillar['map'] %}
# parallel_provision_{{ phase }}:
#  salt.parallel_runners:
#    - runners:
#  {% for type in pillar['map'][phase] %}
#  {% if pillar['types'][type] == 'physical' %}
#        provision_{{ type }}:
#          - name: state.orchestrate
#          - kwarg:
#              mods: orch/bootstrap
#              pillar:
#              arch: {{ pillar['types'][type] }}
#  {% elif pillar['types'][type] == 'virtual' %}
#        provision_{{ type }}:
#          - name: state.orchestrate
#          - kwarg:
#              mods: orch/virtual
#              pillar:
#                type: {{ type }}
#  {% endif %}
#  {% endfor %}
# {% endfor %}
## Bootstrap virtual hosts

##provision_virtual:
##  salt.runner:
##    - name: state.orchestrate
##    - mods: orch/virtual
##    - require:
##      - provision_controller
