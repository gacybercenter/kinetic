{% for phase in pillar['hwmap'] %}
  {% for type in pillar['hwmap'][phase] %}
{{ phase }}_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - mods:
      - orch.test
    - pillar:
        type: {{ type }}
    - parallel: true
  {% endfor %}
{% endfor %}
