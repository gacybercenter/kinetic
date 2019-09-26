{% set type = pillar['type'] %}
{% set style = pillar['types'][type] %}

{% if style == 'physical' %}
{% for address in pillar['hosts'][type]['ipmi_addresses'] %}
zeroize_{{ address }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          target: {{ address }}
          global: True
          api_user: {{ pillar['api_user'] }}
    - parallel: true

sleep_{{ type }}_{{ host }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
{% endfor %}
{% endif %}
