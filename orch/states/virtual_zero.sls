{% set type = pillar['type'] %}

{% for domain in salt['virt.list_domains']() if type in domain %}

stop_{{ domain }}:
  virt.stopped:
    - name: {{ domain }}

remove_{{ domain }}:
  file.absent:
    - name: /kvm/vms/{{ domain }}
    - require:
      - virt: stop_{{ domain }}

remove_{{ domain }}_logs:
  file.absent:
    - name: /var/log/libvirt/{{ domain }}.log
    - require:
      - virt: stop_{{ domain }}

{% endfor %}
