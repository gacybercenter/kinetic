{% set type = pillar['type'] %}
{% set style = pillar['style'] %}
{% set ipmi_password = pillar['ipmi_password'] %}

{% if type == 'physical' %}
zeroize_host:
  salt.function:
    - name: ipmi.raw_command
    - tgt: salt
    - arg:
      - netfn=0x00
      - command=0x08
      - data=[0x05,0xa0,0x04,0x00,0x00,0x00]
    - kwarg:
        api_host: 10.100.0.41
        api_user: ADMIN
        api_pass: {{ ipmi_password }}
{% endif %}
