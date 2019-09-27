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
