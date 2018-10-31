{% for phase in pillar['hwmap'] %}
parallel_provision_{{ phase }}:
  salt.parallel_runners:
    - runners:
  {% for type in pillar['hwmap'][phase] %}
        provision_{{ type }}:
          - name: state.orchestrate
          - kwarg:
              mods: orch/bootstrap
              pillar:
                type: {{ type }}
  {% endfor %}
{% endfor %}
