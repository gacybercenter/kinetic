include:
  - /formulas/bmo/install

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
    - provisioning_interface: {{ pillar['ironic_interface'] }}
    - provisioning_nic: {{ pillar['ironic_interface'] }}
    - provisioning_dhcp_range_start: {{ pillar['ironic_dhcp_start'] }}
    - provisioning_dhcp_range_end: {{ pillar['ironic_dhcp_end'] }}
    - provisioning_dhcp_range_gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
    - provisioning_dhcp_range_netmask: {{ netmask }}
    - inspection_dhcp_all_interfaces: {{ pillar['ironic_interface'] }}
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