{% set type = pillar['type'] %}
{% set style = pillar['types'][type] %}


{% if style == 'physical' %}

# type is the type of host (compute, controller, etc.)
# target is the ip address of the bmc on the target host OR the hostname if zeroize
# is going to be called independently
# global lets the state know that all hosts are being rotated
{% for bmc_address in pillar['hosts'][type]['ipmi_addresses'] %}
zeroize_{{ address }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          target: {{ bmc_address }}
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
zeroize_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          target: {{ type }}
          global: True

sleep_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1

{% for host in range(pillar['virtual'][type]['count']) %}
provision_{{ host }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          spawning: {{ loop.index0 }}
    - parallel: true

sleep_{{ host }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
{% endfor %}
{% endif %}
