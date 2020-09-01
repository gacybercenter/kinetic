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

## Create the special targets dictionary and populate it with the 'id' of the target (either the physical uuid or the spawning)
## as well as its ransomized 'uuid'.
{% set targets = {} %}
{% if style == 'physical' %}
## create and endpoints dictionary of all physical uuids
  {% set endpoints = salt.saltutil.runner('mine.get',tgt='pxe',fun='redfish.gather_endpoints')["pxe"] %}
  {% for id in pillar['hosts'][type]['uuids'] %}
    {% set targets = targets|set_dict_key_value(id+':api_host', endpoints[id]) %}
    {% set targets = targets|set_dict_key_value(id+':uuid', salt['random.get_str']('64')|uuid) %}
  {% endfor %}
{% elif style == 'virtual' %}
  {% set controllers = salt.saltutil.runner('manage.up',tgt='role:controller',tgt_type='grain') %}
  {% set offset = range(controllers|length)|random %}
  {% for id in range(pillar['hosts'][type]['count']) %}
    {% set targets = targets|set_dict_key_value(id|string+':spawning', loop.index0) %}
    {% set targets = targets|set_dict_key_value(id|string+':controller', controllers[(loop.index0 + offset) % controllers|length]) %}
    {% set targets = targets|set_dict_key_value(id|string+':uuid', salt['random.get_str']('64')|uuid) %}
  {% endfor %}
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
          targets: {{ targets }}

provision_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          targets: {{ targets }}
    - require:
      - zeroize_{{ type }}          
