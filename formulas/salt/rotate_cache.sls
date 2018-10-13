{% for address in pillar['hosts']['cache']['ipmi_addresses'] %}
ipmitool chassis bootdev pxe options=efiboot -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run:
    - require_in:
      - ipmitool chassis power reset

ipmitool chassis power reset -U ADMIN -P {{ pillar['ipmi_password'] }} -H {{ address }}:
  cmd.run
{% endfor %}
