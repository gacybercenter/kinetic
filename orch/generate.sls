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

sleep_{{ address }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
{% endfor %}

{% for mac in pillar['hosts'][type]['macs'] %}
{% set uuid = 4294967296 | random_hash | uuid %}
provision_{{ mac }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          target: {{ mac }}
          global: True
          api_user: {{ pillar['api_user'] }}
          uuid: {{ uuid }}
    - parallel: true

sleep_{{ mac }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
{% endfor %}
{% endif %}
