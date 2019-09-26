{% set type = pillar['type'] %}
{% set style = pillar['types'][type] %}
{% set api_pass = pillar['ipmi_password'] %}

{% if style == 'physical' %}
{% set api_host = salt.saltutil.runner('mine.get',tgt='('pillar['target']',fun='bmc_address') %}
zeroize_host:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - salt-call ipmi.raw_command netfn=0x00 command=0x08 data=[0x05,0xa0,0x04,0x00,0x00,0x00] api_host={{ api_host }} api_user=ADMIN api_pass={{ api_pass }}

reboot_host:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - salt-call ipmi.set_power boot wait=5 api_host={{ api_host }} api_user=ADMIN api_pass={{ api_pass }}
{% endif %}

delete_{{ host }}_key:
  salt.wheel:
    - name: key.delete
    - match: '{{ type }}*'
