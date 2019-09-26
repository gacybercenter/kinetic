
{% set target = pillar['target'] %}
{% set type = target.split('-')[0] %}
{% set style = pillar['types'][type] %}
{% set api_pass = pillar['ipmi_password'] %}
{% set api_user = pillar['api_user'] %}

{% if style == 'physical' %}
  {% if salt['pillar.get']('global', 'False') == True %}
    {% set api_host = pillar['address'] %}
  {% else %}
    {% set api_host = salt.saltutil.runner('mine.get',tgt=target,fun='bmc_address')[target] %}
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

{% elif style == 'virtual' %}
destroy_{{ type }}_domain:
  salt.function:
    - name: cmd.run
    - tgt: 'controller*'
    - arg:
      - virsh list | grep {{ type }} | cut -d" " -f 2 | while read id;do virsh destroy $id;done
{% endif %}

delete_{{ target }}_key:
  salt.wheel:
    - name: key.delete
    - match: '{{ target }}'
