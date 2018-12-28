{% set type = pillar['type'] %}

## Bootstrap physical hosts
rotate_{{ type }}:
  salt.state:
    - tgt: 'salt'
    - sls:
      - orch/states/rotate
    - pillar:
          type: {{ type }}
    - concurrent: true

## Wipe all the keys of the type of host we're about to bootstrap
delete_{{ type }}_key:
  salt.wheel:
    - name: key.delete
    - match: '{{ type }}*'
    - require:
      - rotate_{{ type }}

## This is ugly, but it works and I can't find a better way to
## do this right now.  Basically, we read in the number of IPMI
## addresses in the pillar and create that amount of event listeners
## waiting for that amount of hosts to be issued a hostname by the
## pxe server.  Every time a host gets an address, the amount of
## waiting event listeners decrements by one.  If all hosts successfully
## get issued an address within 300 seconds, the orch runner will
## continue to provisioning.  If not, it generally means that a host
## has hard locked or has been otherwise unable to PXE boot.

  {% for address in pillar['hosts'][type]['ipmi_addresses'] %}
wait_for_{{ type }}_{{ address }}_hostname_assignment:
  salt.wait_for_event:
    - name: salt/job/*/ret/pxe
    - event_id: fun
    - id_list:
      - mine.send
    - timeout: 600
    - require:
      - rotate_{{ type }}
  {% endfor %}

provision_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}

## Bootstrap virtual hosts

##provision_virtual:
##  salt.runner:
##    - name: state.orchestrate
##    - mods: orch/virtual
##    - require:
##      - provision_controller
