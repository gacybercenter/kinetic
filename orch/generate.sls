{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}

{% if salt['pillar.get']('universal', False) == False %}
master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true
    - fail_minions:
      - 'salt'

pxe_setup:
  salt.state:
    - tgt: 'pxe'
    - highstate: true
    - fail_minions:
      - 'pxe'
{% endif %}

{% if style == 'physical' %}

# type is the type of host (compute, controller, etc.)
# target is the ip address of the bmc on the target host OR the hostname if zeroize
# is going to be called independently
# global lets the state know that all hosts are being rotated

zeroize_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          provision: True

{% elif style == 'virtual' %}
  {% set controllers = salt.saltutil.runner('manage.up',tgt='role:controller',tgt_type='grain') %}
  {% set offset = range(controllers|length)|random %}
  {% for host in range(pillar['hosts'][type]['count']) %}

zeroize_{{ type }}_{{ host }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          target: {{ type }}
          provision: True
          spawning: {{ loop.index0 }}
          controller: {{ controllers[(loop.index0 + offset) % controllers|length] }}
    - parallel: True

sleep_zeroize_{{ type }}_{{ host }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
  {% endfor %}
{% endif %}
