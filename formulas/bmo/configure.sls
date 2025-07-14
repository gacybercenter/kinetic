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

ensure_{{ name }}_kvm_present:
  virt.defined:
    - name: {{ name }}
    - cpu: {{ pillar['bmh'][name]['cpu'] }}
    - mem: {{ pillar['bmh'][name]['mem'] }}
    - disks:
      - name: disk0
        device: disk
        format: qcow2
        size: {{ pillar['bmh'][name]['disk'] }}
        path: /kvm/vms/{{ name }}/disk01.qcow2
    - interfaces:
      - name: {{ pillar['hosts'][bmh_type]['interface'] }}
        type: bridge
        source: management_br
        mac: {{ pillar['bmh'][name]['bootMACAddress'] }}
    - connection: {{ pillar['bmh'][name]['connection'] }}
    - unless: virsh -c {{ pillar['bmh'][name]['connection'] }} list --all |grep {{ name }}
{% set addrs == pillar['bmh'][name]['bmc']['address'].split('//')[1] %}
ensure_{{ name }}_vbmc_connection:
  cmd.run:
    - name: vbmc add --libvirt-uri {{ pillar['bmh'][name]['connection'] }} --username ADMIN --password {{ pillar['ipmi-password'] }} --address {{ addrs }} --port {{ pillar['bmh'][name]['connection-port'] }} {{ name }}
    - unless: vbmc show --libvirt-uri {{ pillar['bmh'][name]['connection' ] }} {{ name }}
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