{% for phase in pillar['hwmap'] %}
  {% for type in pillar['hwmap'][phase] %}
{{ phase }}_{{ type }}:
  salt.state:
    - tgt: 'salt'
    - sls:
      - orch.test
    - pillar:
        type: {{ type }}
    - parallel: true
    - concurrent: true
  {% endfor %}
{% endfor %}
