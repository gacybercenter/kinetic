{% set type = pillar['type'] %}
{% set style = pillar['types'][type] %}
{% set api_pass = pillar['ipmi_password'] %}
{% set api_host = pillar['api_host'] %}

{% if style == 'physical' %}
zeroize_host:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - salt-call ipmi.raw_command netfn=0x00 command=0x08 data=[0x05,0xa0,0x04,0x00,0x00,0x00] api_host={{ api_host }} api_user=ADMIN api_pass={{ api_pass }}
{% endif %}
