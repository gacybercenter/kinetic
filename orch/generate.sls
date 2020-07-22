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
  {% for uuid in pillar['hosts'][type]['uuids'] %}
zeroize_{{ uuid }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          target: {{ salt.saltutil.runner('mine.get',tgt='pxe',fun='redfish.gather_endpoints')["pxe"][uuid] }} ##this renders to an ip address
          global: True
    - parallel: true

sleep_zeroize_{{ uuid }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
  {% endfor %}

# type is the type of host (compute, controller, etc.)
# target is the mac address of the target host on what ipxe considers net0
# global lets the state know that all hosts are being rotated
  {% for uuid in pillar['hosts'][type]['uuids'] %}
provision_{{ uuid }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          target: {{ uuid }}
          global: True
    - parallel: true

sleep_provision_{{ uuid }}:
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

### Get a list of controllers and set a random offset so the assignments remain balanced
  {% set controllers = salt.saltutil.runner('manage.up',tgt='role:controller',tgt_type='grain') %}
  {% set offset = range(controllers|length)|random %}
  {% for host in range(pillar['hosts'][type]['count']) %}

provision_{{ host }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          controller: {{ controllers[(loop.index0 + offset) % controllers|length] }}
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
