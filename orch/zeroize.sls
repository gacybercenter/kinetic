## This is a collapsed zeroize state that needs to check for two things:
## Is this state called globally?  If so, nuke everything.  If not, nuke the one thing
## Is this device physical, virtual, container, or something else?  The code path depends on this answer

## set local target variable based on pillar data.
## Set type either by calculating it based on target hostname, or use the type value itself
{% set target = pillar['target'] %}
{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}

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

## Follow this codepath if host is virtual
{% elif style == 'virtual' %}
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
