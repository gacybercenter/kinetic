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

# type is the type of host (compute, controller, etc.)
# provision determines whether or not zeroize will just create a blank minion,
# or fully configure it

zeroize_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          provision: True
