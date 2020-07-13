master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

pxe_setup:
  salt.state:
    - tgt: 'pxe'
    - highstate: true

{% for type in pillar['hosts'] %}
  {% for need in pillar['hosts'][type]['needs'] %}
test_echo_{{ needs }}:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ need }} {{ needs }}
  {% endfor %}
{% endfor %}


# parallel_provision_{{ phase }}:
#   salt.parallel_runners:
#     - runners:
#   {% for type in pillar['map'][phase] %}
#         provision_{{ type }}:
#           - name: state.orchestrate
#           - kwarg:
#               mods: orch/generate
#               pillar:
#                 type: {{ type }}
#                 universal: True
