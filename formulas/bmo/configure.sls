include:
  - /formulas/bmo/install

bmo_ironic_env:
  file.managed:
    - name: {{ pillar['script_dir'] }}/config/default/ironic.env
    - source: salt://formulas/bmo/files/ironic.env.j2
    - template: jinja
    - mode: 644

deploy_script:
  file.managed:
    - name: {{ pillar['script_dir'] }}/deploy_state.sh
    - source: salt://formulas/bmo/files/deploy.j2
    - mode: 700
    - template: jinja
    - require:
      - sls: /formulas/bmo/install

{% set subnet_cidr = pillar['networking']['subnets']['management'] %}
{% set cidr_prefix = subnet_cidr.split('/')[1] %}
{% set netmask_result = salt['network_utils.cidr_to_netmask'](cidr_prefix) %}
{% set netmask = netmask_result['netmask'] if netmask_result['success'] else '255.255.255.0' %}

ensure_tls_secret:
  k8s.tls_secret_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - secret_name: ironic-tls
    - common_name: ironic-operator
    - validity_days: 365
    - require:
      - sls: /formulas/ironic-operator/configure

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

ensure_ironic_instance:
  k8s.ironic_instance_present:
    - namespace: {{ pillar['bmo_namespace'] }}
    - instance_name: ironic
    - database_secret_name: ironic-user
    - database_host: ironic-mariadb
    - database_port: 3306
    - database_user: {{ pillar['ironic_username'] }}
    - database_name: ironic
    - http_port: 6385
    - networking_interface: {{ pillar['ironic_interface'] }}
    - networking_ip: {{ pillar['ironic_endpoint_ip'] }}
    - networking_dhcp_range_start: {{ pillar['ironic_dhcp_start'] }}
    - networking_dhcp_range_end: {{ pillar['ironic_dhcp_end'] }}
    - networking_dhcp_range_gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
    - networking_dhcp_network_cidr: {{ pillar['networking']['subnets']['management'] }}
    - networking_dhcp_serve_dns: False
    - networking_dhcp_dns_address: {{ pillar.get('dns_server', '8.8.8.8') }}
    - inspection_dhcp_all_interfaces: False
    - enable_keepalived: True
    - keepalived_vip: {{ pillar['ironic_endpoint_ip'] }}
    - keepalived_interface: {{ pillar['ironic_interface'] }}
    - tls_secret_name: ironic-tls
    - ssh_public_key: {{ pillar['node_deploy_key'] }}
    - api_secret_name: ironic-api-creds
    - api_username: ironic
    - api_password: {{ pillar['ironic_api_password'] }}
    - require:
      - sls: /formulas/bmo/install
      - k8s: ensure_tls_secret

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
check_qemu_address_for_{{ name }}:
  libvirt.check_qemu_address:
    - connection_uri: {{ pillar['bmh'][name]['connection'] }}

# Ensure the storage pool is defined and running
vms_{{ name }}_pool:
  libvirt.pool_running:
    - name: vms
    - ptype: dir
    - target: /kvm/vms
    - connection: {{ pillar['bmh'][name]['connection'] }}
    - require:
      - libvirt: check_qemu_address_for_{{ name }}

# Create the disk volume if it doesn't exist
{{ name }}_disk.qcow2:
  libvirt.volume_define:
    - m_name: {{ name }}_disk0.qcow2
    - pool: vms
    - format: qcow2
    - size: {{ pillar['bmh'][name]['disk'] }}
    - connection: {{ pillar['bmh'][name]['connection'] }}
    - require:
      - libvirt: vms_{{ name }}_pool
      - libvirt: check_qemu_address_for_{{ name }}

# Define the VM using the inline XML string
define_{{name }}_vm:
  libvirt.define_xml_str:
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
            {% for network, config in pillar['hosts'][bmh_type].get('networks', {}).items() %}
            {% set bridge_name = network + '_br' %}
            {% set interface_name = config.get('interfaces')[0] %}
            <interface type='bridge'>
              <source bridge='{{ bridge_name }}'/>
              {% if network == 'management' %}
              <mac address='{{ pillar['bmh'][name]['bootMACAddress'] }}'/>
              {% endif %}
              <alias name='{{ interface_name }}'/>
              <model type='virtio'/>
            </interface>
            {% endfor %}
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
      - libvirt: {{ name }}_disk.qcow2
      - libvirt: check_qemu_address_for_{{ name }}

ensure_{{ name }}_vbmc_connection:
  cmd.run:
    - name: /opt/virtualbmc/bin/vbmc add --libvirt-uri {{ pillar['bmh'][name]['connection'] }} --username ADMIN --password {{ pillar['ipmi-password'] }} --address 127.0.0.1 --port {{ pillar['bmh'][name]['connection-port'] }} {{ name }} && /opt/virtualbmc/bin/vbmc start {{ name }}
    - unless: /opt/virtualbmc/bin/vbmc show {{ name }}
    - require:
      - libvirt: define_{{ name }}_vm
      - libvirt: check_qemu_address_for_{{ name }}
{% endif %}

ensure_{{ name }}_bmh_present:
  k8s.bmh_present:
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_key: bmh
    - require:
      - k8s: ensure_{{ name }}_networkdata_present
      - k8s: ensure_{{ name }}_userdata_present
{% if pillar['hosts'][bmh_type]['style'] == 'virtual' %}
      - libvirt: check_qemu_address_for_{{ name }}
{% endif %}

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
