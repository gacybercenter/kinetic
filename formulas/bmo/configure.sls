include:
  - /formulas/bmo/install

deploy_script:
  file.managed:
    - name: {{ pillar['script_dir'] }}/deploy_state.sh
    - source: salt://formulas/bmo/files/deploy.j2
    - mode: 700
    - template: jinja
{% set subnet_cidr = pillar['networking']['subnets']['management'] %}
{% set cidr_prefix = subnet_cidr.split('/')[1] %}
{% set netmask_result = salt['network_utils.cidr_to_netmask'](cidr_prefix) %}
{% set netmask = netmask_result['netmask'] if netmask_result['success'] else '255.255.255.0' %}
{% for name, host in pillar['bmh'].items() %}
{% set bmh_type = name.split('-')[0].lower() %}
ensure_{{ name }}_bmc_auth_present:
  module.run:
    - name: kinetic-k8s.host_bmc_auth_present
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - ipmi: {{ pillar['ipmi-password'] }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - bmc_auth_template_path: salt://formulas/bmo/files/bmc-auth.j2

ensure_{{ name }}_networkdata_present:
  module.run:
    - name: kinetic-k8s.networkdata_present
    - namespace: baremetal-operator-system
    - defaults:
        'interface': {{ pillar['hosts'][bmh_type]['interface'] }}
        'mac': {{ pillar['bmh'][name]['bootMACAddress'] }}
        'ip': {{ pillar['bmh'][name]['network']['management_ip'] }}
        'prefix': {{ netmask }}
        'gateway': {{ pillar['dhcp-options']['mgmt_gateway'] }}
        'nameserver': {{ pillar['dhcp-options']['dns'] }}
    - bmh_name: {{ name }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - network_template_path: salt://formulas/bmo/files/network-data.j2
    - require:
      - module: ensure_{{ name }}_bmc_auth_present

ensure_{{ name }}_userdata_present:
  module.run:
    - name: kinetic-k8s.userdata_present
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - userdata_template_path: salt://formulas/bmo/files/cloudinit.j2
    - require:
      - module: ensure_{{ name }}_networkdata_present
{% if pillar['hosts'][bmh_type]['style'] == 'virtual' %}
# Debug: Echo the resolved connection for troubleshooting
debug_connection:
  cmd.run:
    - name: echo "Resolved connection: {{ pillar['bmh'][name]['connection'] }}"
# Ensure the storage pool is defined and running
vms_pool:
  virt.pool_running:
    - name: vms
    - ptype: dir
    - target: /kvm/vms
    - connection: {{ pillar['bmh'][name]['connection'] }}

# Create the disk volume if it doesn't exist
create_disk_volume:
  module.run:
    - name: virt.volume_create
    - pool: vms
    - name: {{ name }}_disk0.qcow2
    - format: qcow2
    - size: {{ pillar['bmh'][name]['disk'] * 1073741824 }}  # Convert GiB to bytes
    - connection: {{ pillar['bmh'][name]['connection'] }}
    - require:
      - virt: vms_pool
    - unless: virsh --connect {{ pillar['bmh'][name]['connection'] }} vol-info --pool vms {{ name }}_disk0.qcow2

# Define the VM using the inline XML string
define_vm:
  module.run:
    - name: virt.define_xml_str
    - xml: |
        <domain type='kvm'>
          <name>{{ name }}</name>
          <uuid>{{ pillar['bmh'][name]['uuid'] }}</uuid>
          <memory unit='MiB'>{{ pillar['bmh'][name]['mem'] }}</memory>
          <vcpu>{{ pillar['bmh'][name]['cpu'] }}</vcpu>
          <os>
            <type>hvm</type>
          </os>
          <devices>
            <disk type='volume' device='disk'>
              <source pool='vms' volume='{{ name }}_disk0.qcow2'/>
              <driver name='qemu' type='qcow2'/>
              <target dev='vda' bus='virtio'/>
            </disk>
            <interface type='bridge'>
              <source bridge='management_br'/>
              <mac address='{{ pillar['bmh'][name]['bootMACAddress'] }}'/>
              <alias name='{{ pillar['hosts'][bmh_type]['interface'] }}'/>
              <model type='virtio'/>
            </interface>
            <serial type='pty'>
              <target type='isa-serial' port='0'/>
            </serial>
            <console type='pty'>
              <target type='serial' port='0'/>
            </console>
            <graphics type='spice' autoport='yes'/>
          </devices>
        </domain>
    - connection: {{ pillar['bmh'][name]['connection'] }}
    - require:
      - module: create_disk_volume

ensure_{{ name }}_vbmc_connection:
  cmd.run:
    - name: /opt/virtualbmc/bin/vbmc add --libvirt-uri {{ pillar['bmh'][name]['connection'] }} --username ADMIN --password {{ pillar['ipmi-password'] }} --address 127.0.0.1 --port {{ pillar['bmh'][name]['connection-port'] }} {{ name }}
    - unless: /opt/virtualbmc/bin/vbmc show {{ name }}
    - require:
      - virt: ensure_{{ name }}_kvm_present

{% endif %}
ensure_{{ name }}_bmh_present:
  module.run: 
    - name: kinetic-k8s.bmh_present
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - bmh_template_path: salt://formulas/bmo/files/bmh.j2
    - require:
      - module: ensure_{{ name }}_networkdata_present
      - module: ensure_{{ name }}_userdata_present

# If BMH was recreated, ensure the host-specific BMC auth Secret is recreated
ensure_{{ name }}_bmc_auth_recreated_if_bmh_recreated:
  module.run:
    - name: kinetic-k8s.host_bmc_auth_present
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - ipmi: {{ pillar['ipmi-password'] }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - bmc_auth_template_path: salt://formulas/bmo/files/bmc-auth.j2
    - require:
      - module: ensure_{{ name }}_bmh_present
    - onchanges:
      - module: ensure_{{ name }}_bmh_present
{% endfor %}