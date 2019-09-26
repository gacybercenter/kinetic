{% set type = pillar['type'] %}
{% set style = pillar['style'] %}
{% set ipmi_password = pillar['ipmi_password'] %}

{% if type == 'physical' %}
zeroize_host:
  salt.runner:
    - name: salt.cmd
    - fun: ipmi.raw_command
    - args:
      - netfn=0x00
      - command=0x08
      - data=[0x05,0xa0,0x04,0x00,0x00,0x00]
{% endif %}
