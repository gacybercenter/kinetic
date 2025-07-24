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

{% endfor %}