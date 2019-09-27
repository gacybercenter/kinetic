## This is a collapsed zeroize state that needs to check for two things:
## Is this state called globally?  If so, nuke everything.  If not, nuke the one things
## Is this device physical, virtual, container, or something else?  The code path depends on this answers

## set local target variable based on pillar data.
## Set type either by calculating it based on target hostname, or use the type value itself
{% set target = pillar['target'] %}
{% if salt['pillar.get']('global', 'False') == True %}
  {% set type = pillar['type'] %}
{% else %}
  {% set type = target.split('-')[0] %}
{% endif %}

{% set style = pillar['types'][type] %}

## Follow this codepath if host is physical
{% if style == 'physical' %}
{% set api_pass = pillar['ipmi_password'] %}
{% set api_user = pillar['api_user'] %}
  {% if salt['pillar.get']('global', 'False') == True %}
    {% set api_host = target %}
  {% else %}
    {% set api_host_dict = salt.saltutil.runner('mine.get',tgt=target,fun='bmc_address') %}
    {% set api_host = api_host_dict[target] %}
  {% endif %}

zeroize_host:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - salt-call ipmi.raw_command netfn=0x00 command=0x08 data=[0x05,0xa0,0x04,0x00,0x00,0x00] api_host={{ api_host }} api_user={{ api_user }} api_pass={{ api_pass }}

reboot_host:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - salt-call ipmi.set_power boot wait=5 api_host={{ api_host }} api_user={{ api_user }} api_pass={{ api_pass }}

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
{% endif %}

delete_{{ target }}_key:
  salt.wheel:
    - name: key.delete
{% if salt['pillar.get']('global', 'False') == True %}
    - match: '{{ type }}*'
{% else %}
    - match: {{ target }}
{% endif %}
