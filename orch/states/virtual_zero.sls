{% set type = pillar['type'] %}

{% for domain in salt['virt.list_domains']() if type in domain %}
stop_{{ domain }}:
  virt.powered_off:
    - name: {{ domain }}
    - require_in:
      - remove_{{ domain }}
      - remove_{{ domain }}_logs      
      - report_success
{% endfor %}

{% for domain in salt['file.readdir']('/kvm/vms') if type in domain %}
remove_{{ domain }}:
  file.absent:
    - name: /kvm/vms/{{ domain }}
    - require_in:
      - report_success

remove_{{ domain }}_logs:
  file.absent:
    - name: /var/log/libvirt/{{ domain }}.log
    - require_in:
      - report_success
{% endfor %}

report_success:
  test.nop
