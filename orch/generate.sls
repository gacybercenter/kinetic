{% set type = pillar['type'] %}
{% set style = pillar['types'][type] %}

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
  {% for host, ids in salt['mine.get']('pxe', 'metal.gather') | dictsort() %}
    {% for id in ids %}
      {% if uuid == id %}
zeroize_{{ bmc_address }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          target: {{ ids[id] }}
          global: True
    - parallel: true

sleep_{{ bmc_address }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
      {% endif %}
    {% endfor %}
  {% endfor %}
{% endfor %}

# type is the type of host (compute, controller, etc.)
# target is the mac address of the target host on what ipxe considers net0
# global lets the state know that all hosts are being rotated
{% for uuid in pillar['hosts'][type]['uuids'] %}
  {% for host, ids in salt['mine.get']('pxe', 'metal.gather') | dictsort() %}
    {% for id in ids %}
      {% if uuid == id %}
provision_{{ id }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          target: {{ id }}
          global: True
    - parallel: true

sleep_{{ mac }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
      {% endif %}
    {% endfor %}
  {% endfor %}
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

get_controllers_for_{{ type }}:
  salt.function:
    - name: cmd.shell
    - tgt: 'salt'
    - arg:
      - while true ;
        do if [ $(touch /tmp/{{ type }}_controllers ; cat /tmp/{{ type }}_controllers | wc -l) -lt {{ pillar['virtual'][type]['count'] }} ] ;
        then salt-run manage.up tgt_type="grain" tgt="role:controller" | sed 's/^..//' | shuf >> /tmp/{{ type }}_controllers ;
        else break ;
        fi ;
        done

{% for host in range(pillar['virtual'][type]['count']) %}

provision_{{ host }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          controller: __slot__:salt:cmd.run("sed '{{ loop.index }}q;d' /tmp/{{ type }}_controllers")
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

wipe_controllers_for_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - rm -f /tmp/{{ type }}_controllers

{% endif %}
