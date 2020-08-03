## This is a collapsed zeroize state that needs to check for two things:
## Is this state called globally?  If so, nuke everything.  If not, nuke the one thing
## Is this device physical, virtual, container, or something else?  The code path depends on this answer

## set local target variable based on pillar data.
## Set type either by calculating it based on target hostname, or use the type value itself
{% set target = pillar['target'] %}
{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}
{% set controller = pillar['controller'] %}
{% set uuid =  salt['random.get_str']('64') | uuid %}

## Follow this codepath if host is physical
{% if style == 'physical' %}
  {% set api_pass = pillar['bmc_password'] %}
  {% set api_user = pillar['api_user'] %}
  {% set api_host = target %}

set_bootonce_host:
  salt.function:
    - name: redfish.set_bootonce
    - tgt: pxe
    - arg:
      - {{ api_host }}
      - {{ api_user }}
      - {{ api_pass }}
      - UEFI
      - Pxe

reset_host:
  salt.function:
    - name: redfish.reset_host
    - tgt: pxe
    - arg:
      - {{ api_host }}
      - {{ api_user }}
      - {{ api_pass }}

assign_uuid_to_{{ target }}:
  salt.function:
    - name: file.write
    - tgt: 'pxe'
    - arg:
      - /var/www/html/assignments/{{ target }}
      - {{ type }}
      - {{ type }}-{{ uuid }}
      - {{ pillar['hosts'][type]['os'] }}
      - {{ pillar['hosts'][type]['interface'] }}

## Follow this codepath if host is virtual
{% elif style == 'virtual' %}
{% set spawning = salt['pillar.get']('spawning', 0) %}
  {% if spawning|int == 0 %}
destroy_{{ target }}_domain:
  salt.function:
    - name: cmd.run
    - tgt: 'controller*'
    - arg:
      - virsh list | grep {{ target }} | cut -d" " -f 2 | while read id;do virsh destroy $id;done

wipe_{{ target }}_vms:
  salt.function:
    - name: cmd.run
    - tgt: 'controller*'
    - arg:
      - ls /kvm/vms | grep {{ target }} | while read id;do rm -rf /kvm/vms/$id;done

wipe_{{ target }}_logs:
  salt.function:
    - name: cmd.run
    - tgt: 'controller*'
    - arg:
      - ls /var/log/libvirt | grep {{ target }} | while read id;do rm /var/log/libvirt/$id;done
  {% endif %}

prepare_vm_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: {{ controller }}
    - sls:
      - orch/states/virtual_prep
    - pillar:
        hostname: {{ type }}-{{ uuid }}
    - concurrent: true

{% endif %}

## reboots initiated by the BMC take a few seconds to take effect
## This sleep ensures that the key is only removed after
## the device has actually been rebooted
{{ target }}_wheel_removal_delay:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 5

delete_{{ target }}_key:
  salt.wheel:
    - name: key.delete
    - match: '{{ type }}*'

expire_{{ target }}_dead_hosts:
  salt.function:
    - name: address.expire_dead_hosts
    - tgt: salt

wait_for_provisioning_{{ type }}-{{ uuid }}:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ type }}-{{ uuid }}
{% if style == 'virtual' %}
    - timeout: 180
{% elif style == 'physical' %}
    - timeout: 900
{% endif %}

accept_minion_{{ type }}-{{ uuid }}:
  salt.wheel:
    - name: key.accept
    - match: {{ type }}-{{ uuid }}
    - require:
      - wait_for_provisioning_{{ type }}-{{ uuid }}

wait_for_minion_first_start_{{ type }}-{{ uuid }}:
  salt.wait_for_event:
    - name: salt/minion/{{ type }}-{{ uuid }}/start
    - id_list:
      - {{ type }}-{{ uuid }}
    - timeout: 60
    - require:
      - accept_minion_{{ type }}-{{ uuid }}

sync_all_{{ type }}-{{ uuid }}:
  salt.function:
    - name: saltutil.sync_all
    - tgt: '{{ type }}-{{ uuid }}'
    - require:
      - wait_for_minion_first_start_{{ type }}-{{ uuid }}

{% if style == 'physical' %}
remove_pending_{{ type }}-{{ uuid }}:
  salt.function:
    - name: file.remove
    - tgt: 'pxe'
    - arg:
      - /var/www/html/assignments/{{ target }}
    - require:
      - sync_all_{{ type }}-{{ uuid }}

{% elif style == 'virtual' %}
set_spawning_{{ type }}-{{ uuid }}:
  salt.function:
    - name: grains.set
    - tgt: '{{ type }}-{{ uuid }}'
    - arg:
      - spawning
    - kwarg:
          val: {{ spawning }}
    - require:
      - sync_all_{{ type }}-{{ uuid }}
{% endif %}

{% if salt['pillar.get']('provision', False) == True %}

provision_{{ uuid }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          uuid: {{ uuid }}

{% endif $}
