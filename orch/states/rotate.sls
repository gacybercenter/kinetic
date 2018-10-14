{% set type = pillar['type'] %}
{% for address in pillar['hosts'][type]['ipmi_addresses'] %}

ipmitool -I lanplus chassis bootdev pxe options=efiboot -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run:
    - require_in:
      - ipmitool chassis power reset -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}

{% if salt['cmd.shell']('ipmitool -I lanplus chassis power status -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }} == "Chassis Power is off"')

ipmitool -I lanplus chassis power on -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run

{% else %}

ipmitool -I lanplus chassis power reset -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run

{% endif %}
{% endfor %}
