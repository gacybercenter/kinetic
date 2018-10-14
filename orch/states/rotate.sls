{% for address in pillar['hosts']['type']['ipmi_addresses'] %}
ipmitool -I lanplus chassis bootdev pxe options=efiboot -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run:
    - require_in:
      - ipmitool chassis power reset -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}

ipmitool -I lanplus chassis power reset -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run
{% endfor %}
