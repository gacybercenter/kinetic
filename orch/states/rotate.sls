{% set type = pillar['type'] %}
{% set ipmi_password = pillar['ipmi_password'] %}
{% for address in pillar['hosts'][type]['ipmi_addresses'] %}

ipmitool -I lanplus chassis bootdev pxe options=efiboot -U ADMIN -P {{ ipmi_password }} -H {{ address }}:
  cmd.run

#{% set powerstate = salt['cmd.shell']('ipmitool -I lanplus chassis power status -U ADMIN -P {{ ipmi_password }} -H {{ address }}') %}
{% set powerstate = 'ipmitool -I lanplus chassis power status -U ADMIN -P ipmi_password -H address' %}

echo {{ address }}:
  cmd.run
echo {{ powerstate }}:
  cmd.run

ipmitool -I lanplus chassis power on -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run

ipmitool -I lanplus chassis power reset -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run

{% endfor %}
