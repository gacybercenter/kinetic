{% set type = pillar['type'] %}
{% for address in pillar['hosts'][type]['ipmi_addresses'] %}

ipmitool -I lanplus chassis bootdev pxe options=efiboot -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run

{% set powerstate = salt['cmd.shell']('ipmitool -I lanplus chassis power status -U ADMIN -P pillar['ipmi_password']|e -H {{ address }}') %}

echo {{ powerstate }}:
  cmd.run

ipmitool -I lanplus chassis power on -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run

ipmitool -I lanplus chassis power reset -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run

{% endfor %}
