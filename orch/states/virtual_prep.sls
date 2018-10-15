{% set type = pillar['type'] %}
{% set hostname = type+"-"+pillar['identifier'] %}

/kvm/vms/{{ hostname }}/config.xml:
  file.managed:
    - source: salt://formulas/controller/files/common.xml
    - makedirs: True
    - template: jinja
    - defaults:
        name: {{ hostname }}
        ram: pillar['virtual'][type]['config']['ram'] %}
        cpu: pillar['virtual'][type]['config']['cpu'] %}
        network: |
        {% for network in pillar['virtual'][type]['config']['networks'] %}
          <interface type='bridge'>
            <source bridge='{{ network }}'/>
            <target dev='vnet{{ loop.index0 }}'/>
            <model type='virtio'/>
            <alias name='net{{ loop.index0 }}'/>
          </interface>
        {% endfor %}


/kvm/vms/{{ hostname }}/disk0.raw:
  file.copy:
    - source: /kvm/images/{{ pillar['virtual'][type]['config']['os'] }}-latest

qemu-img resize -f raw /kvm/vms/{{ hostname }}/disk0.raw {{ pillar['virtual'][type]['config']['disk'] }}:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/disk0.raw

/kvm/vms/{{ hostname }}/data/meta-data:
  file.managed:
    - source: salt://formulas/controller/files/common.metadata
    - makedirs: True
    - template: jinja
    - defaults:
        hostname: {{ hostname }}

/kvm/vms/{{ hostname }}/data/user-data:
  file.managed:
    - source: salt://formulas/controller/files/common.userdata
    - makedirs: True
    - template: jinja
    - defaults:
        minion_id: {{ hostname }}

genisoimage -o /kvm/vms/{{ hostname }}/config.iso -V cidata -r -J /kvm/vms/{{ hostname }}/data/meta-data /kvm/vms/{{ hostname }}/data/user-data:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/data/meta-data
      - /kvm/vms/{{ hostname }}/data/user-data

virsh create /kvm/vms/{{ hostname }}/config.xml:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/config.xml
