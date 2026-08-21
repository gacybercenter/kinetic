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

ensure_salt_master_uuids_secret:
  k8s.uuids_present:
    - namespace: salt
    - secret_name: uuids
    - pillar_key: bmh  # Explicitly set to bmh, though it's now the default
    - deployment_name: salt-master
    - wait_timeout: 300
    - wait_interval: 10
    - salt_check_timeout: 120
    - salt_check_interval: 5
    - salt_check_key: bmh

{% for name, host in pillar['bmh'].items() %}
{% set bmh_type = name.split('-')[0].lower() %}
ensure_{{ name }}_bmc_auth_present:
  k8s.host_bmc_auth_present:
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - ipmi: {{ pillar['ipmi-password'] }}
    - pillar_key: bmh

ensure_{{ name }}_networkdata_present:
  k8s.networkdata_present:
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - defaults:
        interface: {{ pillar['hosts'][bmh_type]['interface'] }}
        mac: {{ pillar['bmh'][name]['bootMACAddress'] }}
        ip: {{ pillar['bmh'][name]['network']['management_ip'] }}
        prefix: {{ netmask }}
        gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
        nameserver: {{ pillar['dhcp-options']['dns'] }}
    - pillar_key: bmh
    - require: 
      - k8s: ensure_{{ name }}_bmc_auth_present

ensure_{{ name }}_userdata_present:
  k8s.userdata_present:
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_key: bmh    
    - require:
      - k8s: ensure_{{ name }}_networkdata_present

{% if pillar['hosts'][bmh_type]['style'] == 'virtual' %}
# Ensure the storage pool is defined and running
vms_{{ name }}_pool:
  virt.pool_running:
    - name: vms
    - ptype: dir
    - target: /kvm/vms
    - connection: {{ pillar['bmh'][name]['connection'] }}

# Create the disk volume if it doesn't exist
{{ name }}_disk.qcow2:
  module.run:
    - name: virt.volume_define
    - m_name: {{ name }}_disk0.qcow2
    - pool: vms
    - format: qcow2
    - size: {{ pillar['bmh'][name]['disk'] }}
    - connection: {{ pillar['bmh'][name]['connection'] }}
    - require:
      - virt: vms_{{ name }}_pool
    - unless: virsh --connect {{ pillar['bmh'][name]['connection'] }} vol-info --pool vms {{ name }}_disk0.qcow2

# Define the VM using the inline XML string
define_{{name }}_vm:
  module.run:
    - name: virt.define_xml_str
    - xml: |
        <domain type='kvm'>
          <name>{{ name }}</name>
          <uuid>{{ pillar['bmh'][name]['uuid'] }}</uuid>
          <memory unit='MiB'>{{ pillar['bmh'][name]['mem'] }}</memory>
          <vcpu>{{ pillar['bmh'][name]['cpu'] }}</vcpu>
          <cpu mode='host-passthrough' check='none'/>
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
    - connection: '{{ pillar['bmh'][name]['connection'] }}'
    - require:
      - module: {{ name }}_disk.qcow2

ensure_{{ name }}_vbmc_connection:
  cmd.run:
    - name: /opt/virtualbmc/bin/vbmc add --libvirt-uri {{ pillar['bmh'][name]['connection'] }} --username ADMIN --password {{ pillar['ipmi-password'] }} --address 127.0.0.1 --port {{ pillar['bmh'][name]['connection-port'] }} {{ name }} && /opt/virtualbmc/bin/vbmc start {{ name }}
    - unless: /opt/virtualbmc/bin/vbmc show {{ name }}
    - require:
      - module: define_{{ name }}_vm

{% endif %}
ensure_{{ name }}_bmh_present:
  k8s.bmh_present:
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_key: bmh
    - require:
      - k8s: ensure_{{ name }}_networkdata_present
      - k8s: ensure_{{ name }}_userdata_present

# If BMH was recreated, ensure the host-specific BMC auth Secret is recreated
ensure_{{ name }}_bmc_auth_recreated_if_bmh_recreated:
  k8s.host_bmc_auth_present:
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - ipmi: {{ pillar['ipmi-password'] }}
    - pillar_key: bmh
    - require:
      - k8s: ensure_{{ name }}_bmh_present
    - onchanges:
      - k8s: ensure_{{ name }}_bmh_present
{% endfor %}