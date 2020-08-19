{% set type = pillar['type'] %}


## This can be further improved - see https://docs.saltstack.com/en/master/ref/modules/all/salt.modules.virt.html#salt.modules.virt.vm_info
## and https://libvirt.org/formatdomain.html#elementsMetadata
## we can define custom metadata which is then checked before taking action on a domain (e.g. we set roles/types rather than calcualting them)
{% for domain in salt['virt.list_domains']() if type == domain.split('-')[0] %}
stop_{{ domain }}:
  virt.powered_off:
    - name: {{ domain }}
    - require_in:
      - remove_{{ domain }}
      - remove_{{ domain }}_logs
      - report_success
{% endfor %}

{% for domain in salt['file.readdir']('/kvm/vms') if type == domain.split('-')[0] %}
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
