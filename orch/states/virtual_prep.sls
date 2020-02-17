{% set hostname = pillar['hostname'] %}
{% set type = hostname.split('-')[0] %}

/kvm/vms/{{ hostname }}/config.xml:
  file.managed:
    - source: salt://formulas/controller/files/common.xml
    - makedirs: True
    - template: jinja
    - defaults:
        name: {{ hostname }}
        ram: {{ pillar['virtual'][type]['ram'] }}
        cpu: {{ pillar['virtual'][type]['cpu'] }}
        networks: |
        {% for interface in pillar['virtual'][type]['networks']['interfaces']|sort() %}
          <interface type='bridge'>
            <source bridge='{{ pillar['virtual'][type]['networks']['interfaces'][interface]['network'] }}'/>
            <target dev='vnet{{ loop.index0 }}'/>
            <model type='virtio'/>
            <alias name='net{{ loop.index0 }}'/>
            <mac address='{{ salt['generate.mac']('52:54:00') }}'/>
          </interface>
        {% endfor %}
        {% if grains['os_family'] == 'Debian' %}
        seclabel: <seclabel type='dynamic' model='apparmor' relabel='yes'/>
        {% elif grains['os_family'] == 'RedHat' %}
        seclabel: <seclabel type='dynamic' model='selinux' relabel='yes'/>
        {% endif %}

/kvm/vms/{{ hostname }}/disk0.raw:
  file.copy:
    - source: /kvm/images/{{ pillar['virtual'][type]['os'] }}-latest

qemu-img resize -f raw /kvm/vms/{{ hostname }}/disk0.raw {{ pillar['virtual'][type]['disk'] }}:
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
        hostname: {{ hostname }}
        master_record: {{ pillar['master_record'] }}
        transport: "\'{ \"transport\": \"{{ pillar['salt_transport'] }}\" }\'"

genisoimage -o /kvm/vms/{{ hostname }}/config.iso -V cidata -r -J /kvm/vms/{{ hostname }}/data/meta-data /kvm/vms/{{ hostname }}/data/user-data:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/data/meta-data
      - /kvm/vms/{{ hostname }}/data/user-data

virsh create /kvm/vms/{{ hostname }}/config.xml:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/config.xml
