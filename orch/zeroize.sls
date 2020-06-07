## This is a collapsed zeroize state that needs to check for two things:
## Is this state called globally?  If so, nuke everything.  If not, nuke the one thing
## Is this device physical, virtual, container, or something else?  The code path depends on this answer

## set local target variable based on pillar data.
## Set type either by calculating it based on target hostname, or use the type value itself
{% set target = pillar['target'] %}
{% if salt['pillar.get']('global', False) == True %}
  {% set type = pillar['type'] %}
{% else %}
  {% set type = target.split('-')[0] %}
{% endif %}

{% set style = pillar['types'][type] %}

## Follow this codepath if host is physical
{% if style == 'physical' %}
{% set api_pass = pillar['bmc_password'] %}
{% set api_user = pillar['api_user'] %}
  {% if salt['pillar.get']('global', False) == True %}
    {% set api_host = target %}
  {% else %}
    {% set api_host_uuid = salt.saltutil.runner('mine.get',tgt=target,fun='host_uuid') %}
    {% for host, ids in salt.saltutil.runner('mine.get',tgt='pxe',fun='redfish.gather_endpoints') | dictsort() %}
      {% for id in ids %}
        {% if api_host_uuid == id %}
          {% set api_host = ids[id] %}
        {% endif %}
      {% endfor %}
    {% endfor %}
  {% endif %}

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

delete_{{ target }}_key:
  salt.wheel:
    - name: key.delete
{% if salt['pillar.get']('global', False) == True %}
    - match: '{{ type }}*'
{% else %}
    - match: {{ target }}
{% endif %}

expire_{{ target }}_dead_hosts:
  salt.function:
    - name: address.expire_dead_hosts
    - tgt: salt
