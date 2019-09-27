{% set type = pillar['type'] %}
{% set style = pillar['types'][type] %}


{% if style == 'physical' %}

# type is the type of host (compute, controller, etc.)
# target is the ip address of the bmc on the target host
# global lets the state know that all hosts are being rotated
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
    - parallel: true

sleep_{{ address }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
{% endfor %}

# type is the type of host (compute, controller, etc.)
# target is the mac address of the target host on what ipxe considers net0
# global lets the state know that all hosts are being rotated
{% for mac in pillar['hosts'][type]['macs'] %}
provision_{{ mac }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          target: {{ mac }}
          global: True
    - parallel: true

sleep_{{ mac }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
{% endfor %}

{% elif style == 'virtual' %}
nop:
  test.nop
{% endif %}
